# TODOs

Run each command from the repository root. The first three bugs are already
fixed in the working tree (the first two by the Faraday migration) and only
need filing for the record. The fourth is a security issue: report it
privately, not as a public issue.

The commands use bash heredocs, which fish does not support. Start `bash`
first, then paste a command. Each command adds the `bug` label; drop
`--label bug` if the repository has no such label.

## - [ ] File: `revoke` raises `OAuth2::Error` instead of `Procore::OAuthError`

~~~sh
gh issue create --label bug --title 'Token revoke failure raises OAuth2::Error instead of Procore::OAuthError' --body-file - <<'EOF'
## Summary

When the token revoke request fails, `Procore::Client#revoke` raises a raw
`OAuth2::Error` instead of `Procore::OAuthError`, so callers who rescue the
gem's documented errors don't catch it.

## Steps to reproduce

```ruby
credentials = Procore::Auth::AccessTokenCredentials.new(
  client_id: "id",
  client_secret: "secret",
  host: "https://login.example.com",
)
# With POST /oauth/revoke returning HTTP 500:
credentials.revoke(token: token)
```

## Expected

`Procore::OAuthError`, with the failed response attached.

## Actual

`OAuth2::Error` (a `StandardError`).

## Cause

`lib/procore/auth/access_token_credentials.rb`:

```ruby
def revoke(token:)
  # ...
  client.request(:post, "/oauth/revoke", body: request)
rescue RestClient::ExceptionWithResponse
  raise OAuthError.new(e.description, response: e.response)
end
```

- The request is made by the oauth2 gem, which uses Faraday and raises
  `OAuth2::Error`, never `RestClient::ExceptionWithResponse`, so the rescue
  never matches.
- If it did match, it would raise `NameError`, because the exception isn't
  bound (`=> e` is missing).
- `Procore::Client#revoke` only rescues `RuntimeError`, which `OAuth2::Error`
  is not, so the error reaches the caller unchanged.

## Suggested fix

Rescue `OAuth2::Error => e` and raise `OAuthError.new(e.description, response: e.response)`,
matching `#refresh` in the same class. Add a test for a failed revoke.
EOF
~~~

## - [ ] File: request ID is never logged

~~~sh
gh issue create --label bug --title 'Request logs never include the X-Request-Id' --body-file - <<'EOF'
## Summary

The "API Request Finished" and "API Request Failed" log lines are meant to
include the response's `X-Request-Id`, but the value is always empty, so logs
can't be matched to Procore's server-side request IDs.

## Steps to reproduce

1. Set `Procore.configuration.logger` to a `Logger`.
2. Make any request whose response includes `X-Request-Id: req-123`.

## Expected

The log line contains `request_id: req-123`.

## Actual

`request_id` is empty. `response.headers[:x_request_id]` returns `"req-123"`,
so the header is received; only the log lookup is wrong.

## Cause

`lib/procore/requestable.rb`, in `with_response_handling`:

```ruby
request_id: result.headers["x-request-id"],
```

rest-client stores response headers under underscored symbol keys
(`:x_request_id`), so looking up the string `"x-request-id"` always returns
`nil`.

## Suggested fix

Read `response.headers[:x_request_id]` from the `Procore::Response`, which
keeps the same key once the HTTP client is replaced. Add a test that captures
the log output and checks for the request ID.
EOF
~~~

## - [ ] File: `delete` ignores `company_id`

~~~sh
gh issue create --label bug --title 'delete ignores options:, so company_id is never sent' --body-file - <<'EOF'
## Summary

`Procore::Client#delete` ignores its `options:` argument, so
`options: { company_id: ... }` never produces the `Procore-Company-Id` header.
Every other request method sends it. On multi-company (MPZ) accounts, DELETE
requests that need the header can fail or hit the wrong company.

## Steps to reproduce

```ruby
client.delete("projects/1", options: { company_id: 42 })
```

## Expected

The request includes `Procore-Company-Id: 42`.

## Actual

The header is missing.

## Cause

`lib/procore/requestable.rb`, in `#delete`:

```ruby
headers: headers.merge(params: query),
```

It calls `headers` without `options`, so the company and idempotency headers
are never added. The other methods call `headers(options)`.

## Fix

Use `headers(options)`, as the other methods do. Covered by
`test_delete_with_company_id` in `test/procore/requestable_test.rb`.
EOF
~~~

## - [ ] Report privately: DELETE requests log the access token

`SECURITY.md` asks for vulnerabilities to be reported privately. Don't open a
public issue for this one. Use **Report a vulnerability** at
https://github.com/procore-oss/ruby-sdk/security and paste the text below.
The fix is already in the working tree.

**Title:** Access token written to logs on DELETE requests

**Weakness:** CWE-532: Insertion of Sensitive Information into Log File

**Affected versions:** 1.3.1 and earlier (the first affected version has not
been checked)

**Description:**

> When a logger is configured (`Procore.configuration.logger`), every
> `Procore::Client#delete` call writes the full request headers to the log,
> including `Authorization: Bearer <access token>`. Anyone who can read the
> application's logs, or any log aggregation service they're shipped to, can
> obtain a valid Procore access token and call the API as that user until the
> token expires. No other request method logs headers.
>
> **Steps to reproduce**
>
> ```ruby
> Procore.configure { |config| config.logger = Logger.new($stdout) }
> client.delete("projects/1")
> # The "API Request Initiated" line includes
> # "Authorization" => "Bearer <access token>"
> ```
>
> **Cause:** `lib/procore/requestable.rb`, `#delete`, passes
> `headers: headers(options)` to `Util.log_info`.
>
> **Fix:** remove `headers:` from that log call. A test that captures the log
> output and checks the token is absent
> (`test_delete_does_not_log_access_token`) covers it.
>
> **Advice for users:** after upgrading, revoke or rotate access tokens that may
> have been logged, and purge DELETE request lines from existing logs.

## Bugs

Found in the 2026-10-26 review against `reference/combined_OAS.json`. Fix
test-first; each item names the test that should fail before the fix.

- [x] **Gem breaks without a full ActiveSupport load.** `lib/procore.rb` only
  requires `active_support/hash_with_indifferent_access`, but the code uses
  three core extensions it never requires. Outside Rails: the Session, Redis
  and Dalli stores serialize a token as `"#<Procore::Auth::Token:0x...>"`
  (`Object#to_json`), so every request raises `MissingTokenError`; `sync`
  raises `NoMethodError` on `deep_merge`; `OAuthError` with a response raises
  `NoMethodError` on `presence`. Require the extensions where they are used
  and tighten the gemspec's `activesupport > 2.4` constraint.
  Test: `test/procore/standalone_load_test.rb` (subprocess, like
  `test_requiring_procore_does_not_load_rest_client`).
- [x] **Empty response bodies parse to the String `"{}"`.**
  `lib/procore/response.rb` defaults the raw body to `"{}".to_json`, which is
  the JSON string literal `"\"{}\""`. The spec has 235 operations returning
  204 No Content; `response.body` on those is a String, not a Hash.
  Test: `test/procore/response_test.rb`, empty and nil bodies give `{}`.
- [x] **Pagination drops the API version.** `Response#parse_pagination`
  strips the `rest/vX.Y` or `vapid` prefix, so `client.get(pagination[:next])`
  uses `default_version`. About half the spec's paths are v1.1, v2.0 or v2.1,
  and following their links silently hits the wrong version. Decide the
  public shape first (keep the version in the URL, or accept absolute URLs).
  Test: `test/procore/requestable_test.rb`, following a v1.1 next link
  requests `/rest/v1.1/...`.
- [x] **README documents methods that do not exist.** `e.response.errors`
  raises `NoMethodError` (`Response` has `body`, not `errors`), and
  `rescue Procore:Error` has a single colon. No test; documentation only.
- [x] **`Accepts` is not an HTTP header.** `Requestable#headers` sends
  `Accepts: application/json`; the header is `Accept`. Harmless today because
  Procore defaults to JSON, but it is wrong and the spec has an endpoint that
  requires `Accept: text/csv`.
  Test: `test/procore/requestable_test.rb` header expectations use `Accept`.
