require "test_helper"

# The test suite loads ActiveRecord and ActionPack, which pull in every
# ActiveSupport core extension. An application that is not Rails only gets
# what the gem itself requires, so these tests run a script in a fresh
# process with nothing but `require "procore"`.
class Procore::StandaloneLoadTest < Minitest::Test
  def run_standalone(script)
    output = IO.popen(
      [RbConfig.ruby, "-Ilib", "-e", script],
      err: [:child, :out],
      &:read
    )

    [$?.success?, output]
  end

  def test_session_store_round_trips_a_token
    passed, output = run_standalone(<<~RUBY)
      require "procore"

      store = Procore::Auth::Stores::Session.new(session: {})
      store.save(
        Procore::Auth::Token.new(
          access_token: "access",
          refresh_token: "refresh",
          expires_at: 123,
        ),
      )
      token = store.fetch

      exit(token.access_token == "access" && token.expires_at == 123)
    RUBY

    assert passed, output
  end

  def test_sync_combines_batched_responses
    passed, output = run_standalone(<<~RUBY)
      require "procore"

      class Request
        include Procore::Requestable

        def access_token = "token"
        def base_api_path = "http://test.com"
        def options = { default_version: "v1.0" }

        private

        # Answers each batch without a network, with the shape a sync returns.
        def perform(_method, _url, headers:, params: nil, body: nil)
          Faraday::Response.new(
            Faraday::Env.from(
              status: 200,
              body: { entities: [JSON.parse(body)["updates"].first], errors: [] }.to_json,
              response_headers: {},
              request_headers: headers,
              url: URI("http://test.com/rest/v1.0/projects/sync"),
              method: :patch,
            ),
          )
        end
      end

      response = Request.new.sync(
        "projects/sync",
        body: { updates: [{ id: 1 }, { id: 2 }] },
        options: { batch_size: 1 },
      )

      exit(response.body["entities"].map { |e| e["id"] } == [1, 2])
    RUBY

    assert passed, output
  end

  def test_oauth_error_keeps_the_failed_response
    passed, output = run_standalone(<<~RUBY)
      require "procore"

      oauth_response = Struct.new(:status, :parsed, :body, :headers)
        .new(401, nil, "invalid_grant", {})
      error = Procore::OAuthError.new("refresh failed", response: oauth_response)

      exit(error.response.code == 401 && error.response.body == "invalid_grant")
    RUBY

    assert passed, output
  end
end
