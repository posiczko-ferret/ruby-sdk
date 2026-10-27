require "test_helper"

class Procore::Auth::AccessTokenCredentialsTest < Minitest::Test
  def test_refresh_token
    stub_request(:post, "https://procore.example.com/oauth/token")
      .with(body: {
              "client_id" => "id",
              "client_secret" => "secret",
              "grant_type" => "refresh_token",
              "refresh_token" => "refresh",
            })
      .to_return(
        status: 200,
        body: {
          "access_token": "New Token",
          "token_type": "bearer",
          "expires_in": 7200,
          "refresh_token": "New Refresh",
          "created_at": Time.now.to_i,
        }.to_json,
        headers: { "Content-Type" => "application/json" },
      )

    credentials = Procore::Auth::AccessTokenCredentials.new(
      client_id: "id",
      client_secret: "secret",
      host: "https://procore.example.com",
    )

    new_token = credentials.refresh(token: "token", refresh: "refresh")

    assert_equal "New Token", new_token.access_token
    assert_equal "New Refresh", new_token.refresh_token
    refute new_token.expired?
  end

  def test_oauth_client_error_with_html
    stub_request(:post, "https://procore.example.com/oauth/token")
      .with(body: {
              "client_id" => "id",
              "client_secret" => "secret",
              "grant_type" => "refresh_token",
              "refresh_token" => "refresh",
            })
      .to_return(
        status: 500,
        body: "<html><body><h1>This is very bad</h1></body></html>",
        headers: { "Content-Type" => "text/html" },
      )

    credentials = Procore::Auth::AccessTokenCredentials.new(
      client_id: "id",
      client_secret: "secret",
      host: "https://procore.example.com",
    )

    error = assert_raises Procore::OAuthError do
      credentials.refresh(token: "token", refresh: "refresh")
    end

    assert_equal 500, error.response.code
    assert_equal "<html><body><h1>This is very bad</h1></body></html>", error.response.body
    assert_equal({ "content-type" => "text/html" }, error.response.headers)
    assert_nil error.response.request.path
    assert_equal({}, error.response.request.options)
  end

  def test_oauth_client_error_with_json
    stub_request(:post, "https://procore.example.com/oauth/token")
      .with(body: {
              "client_id" => "id",
              "client_secret" => "secret",
              "grant_type" => "refresh_token",
              "refresh_token" => "refresh",
            })
      .to_return(
        status: 500,
        body: { error: "Some bad error" }.to_json,
        headers: { "Content-Type" => "application/json" },
      )

    credentials = Procore::Auth::AccessTokenCredentials.new(
      client_id: "id",
      client_secret: "secret",
      host: "https://procore.example.com",
    )

    error = assert_raises Procore::OAuthError do
      credentials.refresh(token: "token", refresh: "refresh")
    end

    assert_equal 500, error.response.code
    assert_equal({ "error" => "Some bad error" }, error.response.body)
    assert_equal({ "content-type" => "application/json" }, error.response.headers)
    assert_nil error.response.request.path
    assert_equal({}, error.response.request.options)
  end

  def test_connection_failed_error
    stub_request(:post, "https://procore.example.com/oauth/token")
      .with(body: {
              "client_id" => "id",
              "client_secret" => "secret",
              "grant_type" => "refresh_token",
              "refresh_token" => "refresh",
            }).to_timeout

    credentials = Procore::Auth::AccessTokenCredentials.new(
      client_id: "id",
      client_secret: "secret",
      host: "https://procore.example.com",
    )

    assert_raises Procore::APIConnectionError do
      credentials.refresh(token: "token", refresh: "refresh")
    end
  end

  def test_bad_uri_error
    stub_request(:post, "https://procore.example.com/oauth/token")
      .with(
        body: {
          "client_id" => "id",
          "client_secret" => "secret",
          "grant_type" => "client_credentials",
        },
      )

    credentials = Procore::Auth::AccessTokenCredentials.new(
      client_id: "id",
      client_secret: "secret",
      host: "invalid-uri",
    )

    error = assert_raises Procore::OAuthError do
      credentials.refresh(token: "token", refresh: "refresh")
    end

    assert_equal "Host is not a valid URI. Check your host option to make sure it is a properly formed url", error.message
  end

  def test_revoke_failure_raises_oauth_error
    stub_request(:post, "https://procore.example.com/oauth/revoke")
      .to_return(
        status: 500,
        body: { error: "Some bad error" }.to_json,
        headers: { "Content-Type" => "application/json" },
      )
    credentials = Procore::Auth::AccessTokenCredentials.new(
      client_id: "id",
      client_secret: "secret",
      host: "https://procore.example.com",
    )
    token = Procore::Auth::Token.new(
      access_token: "token",
      refresh_token: "refresh",
      expires_at: 0,
    )

    error = assert_raises Procore::OAuthError do
      credentials.revoke(token: token)
    end

    assert_equal 500, error.response.code
  end
end
