# 1. Replace rest-client with Faraday

Date: 2026-10-14

## Status

Accepted

## Context

`Procore::Requestable` sends every API request through `rest-client`. Its last
release, 2.1.0, was in 2019, and the project is effectively unmaintained. It
holds back the dependency tree: `http-accept` is pinned below 2.0 because of
it.

rest-client is used almost entirely in `lib/procore/requestable.rb`, but its
types show through the public API in a few places:

- `Response#headers` is rest-client's header hash, with keys converted to
  symbols (`:link`, `:content_type`). The README tells users to inspect
  `e.response.headers`, and pagination reads `headers[:link]`.
- `Response#request` returns a `RestClient::Request`. It is public but
  undocumented.
- File uploads work by passing a `File` in `body:`. rest-client detects it and
  sends `multipart/form-data`.
- The cause attached to `APIConnectionError` is a rest-client exception.

Two existing bugs come from the rest-client coupling:

- `AccessTokenCredentials#revoke` rescues `RestClient::ExceptionWithResponse`,
  but oauth2 makes its calls through Faraday, so the rescue never runs. It also
  refers to an unbound `e`.
- The request logs look up `headers["x-request-id"]` with a string key, but
  rest-client stores headers under symbol keys (`:x_request_id`), so the
  logged request ID is likely always `nil`.

Options considered:

- **Faraday.** Actively maintained, and already installed because oauth2
  depends on it. Each client gets its own connection object, and the HTTP
  adapter can be swapped. Multipart and retries come from the
  `faraday-multipart` and `faraday-retry` gems, both from the same maintainers.
- **HTTParty.** Maintained, with multipart built in. It would be a new gem with
  its own dependencies (`multi_xml`, `csv`, `mini_mime`), and it is built around
  configuring a class, which suits applications more than libraries.
- **Net::HTTP.** Ships with Ruby, so no new gems. Multipart encoding, retries and
  nested query encoding would all be code we write and maintain.

## Decision

Replace rest-client with Faraday, using `faraday-multipart` for uploads and
`faraday-retry` for retries. Keep the public API of `Procore::Client`
unchanged:

- **Request methods:** `get`, `post`, `put`, `patch`, `delete` and `sync` keep
  their signatures and return types.
- **Errors:** responses keep mapping to the existing `Procore::*` errors.
  Connection failures that remain after retries still raise
  `Procore::APIConnectionError`.
- **Configuration:** `Procore.configuration.timeout` maps to Faraday's
  `request.timeout`. `max_retries` maps to the retry middleware's `max`.
- **Headers:** `Response#headers` keeps its symbol-keyed shape (`:link`,
  `:x_request_id`). The gem converts Faraday's headers into that shape inside
  `Procore::Response`.
- **Request:** `Response#request` returns a small Procore-owned struct instead
  of a `RestClient::Request`, following the stand-in structs `OAuthError`
  already uses. It answers the same calls with the same values rest-client
  gives today, so code reading them keeps working:
  - `url`: the full URL including the query string
    (`http://…/rest/v1.0/projects?per_page=5`).
  - `method`: the HTTP method as a lowercase string (`"get"`), not a symbol.
  - `headers`: the request headers as sent, keyed by header name
    (`"Authorization"`).
  - `payload`: the request body as a string. With rest-client this is a
    `RestClient::Payload` whose stream is already closed, so reading it raises
    `IOError`; no caller can depend on it, and it is not a compatibility
    promise.

  The gem does not define any `RestClient::*` classes to imitate rest-client.
  An app that also loads the real rest-client would get clashing definitions.
- **Uploads:** the gem detects `File`/`IO` values in `body:` and wraps them in
  `Faraday::Multipart::FilePart`, so upload calls do not change. Each file
  part's content type is guessed from its extension with `mime-types`, as
  rest-client did, which keeps `mime-types` as a direct dependency.
- **Connection failures:** DNS failures, unreachable hosts and TLS errors raise
  `Procore::APIConnectionError`. Today they escape as `SocketError`,
  `Errno::EHOSTUNREACH` and `RestClient::SSLCertificateNotVerified`.
- **Redirects:** GET requests keep following redirects, as rest-client does.
  Faraday does not follow them by default, so this needs either the
  `faraday-follow_redirects` gem or a small redirect loop in `Requestable`.
- **`HTTP_EXCEPTIONS`:** this public constant lists only Ruby and Faraday
  exception classes, with no rest-client ones.
- **Loading the gem:** `require "procore"` no longer defines `RestClient` in the
  caller's process.

`test/procore/rest_client_leakage_test.rb` holds tests for these points. Nine of
them fail until the migration is done; that file is the migration's acceptance
check.

The retry middleware is configured to match the current retry behaviour, not
Faraday's defaults:

- **Methods:** retry all methods, including `post` and `patch`. Faraday retries
  only idempotent methods by default. The current code retries every method,
  and `post`/`patch` can carry idempotency tokens.
- **Exceptions:** retry on timeouts and connection failures
  (`Faraday::TimeoutError`, `Faraday::ConnectionFailed`, `Errno::ECONNREFUSED`,
  `Errno::ECONNRESET`).
- **Statuses:** do not retry on HTTP status codes. The current code does not
  retry 429 or 5xx responses, and changing that is a separate decision.
- **Backoff:** `interval: 1.5` and `backoff_factor: 1.5`, which gives the
  current waits of 1.5 s, 2.25 s, 3.375 s and so on.

`Procore::OAuthError` is also in today's retry list. It is raised while the
access token is fetched, before Faraday sends the request, so the retry
middleware cannot see it. Token fetching keeps its own retry inside
`Requestable`.

## Consequences

- One unmaintained runtime dependency (`rest-client`, and with it
  `http-accept`, `http-cookie` and `netrc`) is replaced by `faraday-multipart`
  and `faraday-retry`. `faraday` and `mime-types` are now declared directly;
  before, they arrived through oauth2 and rest-client.
- `Response#request` changes type. Code that calls rest-client-specific methods
  on it breaks. This ships in 2.0.0 alongside the Ruby 3.3 minimum and is listed
  in the CHANGELOG.
- `APIConnectionError#cause` becomes a Faraday exception instead of a
  rest-client one.
- The `revoke` rescue and the request-ID logging are fixed as part of the
  migration.
- Before the switch, tests pin the behaviour users depend on: the shape of
  `Response#headers`, nested query encoding (`filters[foo]=1`,
  `ids[]=1&ids[]=2`), multipart uploads, and the retry count and backoff.

## Upgrade guide

This section is written for users of the gem and is meant to be copied into the
README or the 2.0.0 release notes once the migration ships.

### Upgrading to 2.0: rest-client replaced by Faraday

The gem now sends requests with [Faraday](https://lostisland.github.io/faraday/)
instead of rest-client. The request methods (`get`, `post`, `put`, `patch`,
`delete`, `sync`), their arguments, `Procore::Response` and the configuration
options are unchanged. What changes is mostly which exceptions you see.

#### Exceptions

Every failure now raises a `Procore::Error` subclass, so
`rescue Procore::Error` catches anything the client raises for a failed request.

| Failure                           | 1.x raises                              | 2.0 raises               | `cause` in 1.x                                        | `cause` in 2.0              |
|-----------------------------------|-----------------------------------------|--------------------------|-------------------------------------------------------|-----------------------------|
| HTTP 401                          | `AuthorizationError`                    | unchanged                | –                                                     | –                           |
| HTTP 403                          | `ForbiddenError`                        | unchanged                | –                                                     | –                           |
| HTTP 404                          | `NotFoundError`                         | unchanged                | –                                                     | –                           |
| HTTP 400, 422                     | `InvalidRequestError`                   | unchanged                | –                                                     | –                           |
| HTTP 429                          | `RateLimitError`                        | unchanged                | –                                                     | –                           |
| Any other non-2xx status          | `ServerError`                           | unchanged                | –                                                     | –                           |
| Connect timeout                   | `APIConnectionError`                    | unchanged                | `RestClient::Exceptions::OpenTimeout`                 | `Faraday::ConnectionFailed` |
| Read timeout                      | `APIConnectionError`                    | unchanged                | `RestClient::Exceptions::ReadTimeout`                 | `Faraday::TimeoutError`     |
| Connection refused                | `APIConnectionError`                    | unchanged                | `Errno::ECONNREFUSED`                                 | `Faraday::ConnectionFailed` |
| Connection reset                  | `APIConnectionError`                    | unchanged                | `Errno::ECONNRESET`                                   | `Faraday::ConnectionFailed` |
| Server closed the connection      | `APIConnectionError`                    | unchanged                | `RestClient::ServerBrokeConnection`                   | `Faraday::ConnectionFailed` |
| Access token could not be fetched | `APIConnectionError`                    | unchanged                | `Procore::OAuthError`                                 | unchanged                   |
| TLS certificate error             | `RestClient::SSLCertificateNotVerified` | **`APIConnectionError`** | –                                                     | `Faraday::SSLError`         |
| DNS lookup failed                 | `SocketError`                           | **`APIConnectionError`** | –                                                     | `Faraday::ConnectionFailed` |
| Host unreachable                  | `Errno::EHOSTUNREACH`                   | **`APIConnectionError`** | –                                                     | `Faraday::ConnectionFailed` |

The retry behaviour is unchanged: timeouts, refused and reset connections, and
token fetch failures are retried `max_retries` times with backoff before
`APIConnectionError` is raised. HTTP error statuses, including 429 and 5xx, are
not retried. Every request method is retried, including `post` and `patch`.

**What to change**

- **Rescuing rest-client or socket errors:** rescue `Procore::APIConnectionError`
  instead.

  ```ruby
  # 1.x
  rescue RestClient::SSLCertificateNotVerified, SocketError, Errno::EHOSTUNREACH => e

  # 2.0
  rescue Procore::APIConnectionError => e
  ```

- **Inspecting `cause`:** code that checks for a specific rest-client or `Errno`
  class needs the Faraday class from the table. Faraday keeps the underlying
  error, so the original `Errno` is still reachable as
  `e.cause.wrapped_exception`.

  ```ruby
  # 1.x
  retry_later if e.cause.is_a?(Errno::ECONNREFUSED)

  # 2.0
  retry_later if e.cause.wrapped_exception.is_a?(Errno::ECONNREFUSED)
  ```

- **`Procore::Requestable::HTTP_EXCEPTIONS`:** if you read this constant, it now
  lists Faraday exception classes instead of `RestClient::Exceptions::Timeout`
  and `RestClient::ServerBrokeConnection`.

#### Other changes

- **`Response#request` is no longer a `RestClient::Request`.** It is a small
  Procore object. `url`, `method` (a lowercase string such as `"get"`) and
  `headers` return the same values as before. `payload` now returns the request
  body as a string; in 1.x, reading it raised `IOError`.
- **Integer header values are sent as strings.** `company_id` and
  `idempotency_token` may still be passed as Integers.
- **The gem no longer loads rest-client.** If your application uses
  `RestClient` directly but only got it through this gem, add it to your
  Gemfile:

  ```ruby
  gem "rest-client"
  ```
