require "test_helper"

class Procore::ClientTest < Minitest::Test
  include AuthStubs
  include Database

  def setup
    setup_db
  end

  def test_client_creation
    store = Procore::Auth::Stores::Memory.new(key: 1)
    client = Procore::Client.new(
      client_id: "client id",
      client_secret: "client secret",
      store: store,
    )

    assert_equal "https://procore.example.com", client.options[:host]
    assert_equal Procore::Defaults::USER_AGENT, client.options[:user_agent]
  end

  def test_client_option_overrides
    store = Procore::Auth::Stores::Memory.new(key: 1)
    client = Procore::Client.new(
      client_id: "client id",
      client_secret: "client secret",
      store: store,
      options: {
        host: "https://example.com",
        login_host: "https://my-auth-provider.com",
        default_version: "v1.0",
        user_agent: "Procore Test Suite",
      },
    )

    assert_equal "https://example.com", client.options[:host]
    assert_equal "Procore Test Suite", client.options[:user_agent]
    assert_equal "https://my-auth-provider.com", client.options[:login_host]
  end

  def test_client_active_recored_expired_token
    stub_refresh_token
    stub_request(:get, "https://procore.example.com/rest/v1.0/me")

    user = User.create(
      access_token: "token",
      refresh_token: "refresh",
      expires_at: 2.hours.ago,
    )

    store = Procore::Auth::Stores::ActiveRecord.new(object: user)
    client = Procore::Client.new(
      client_id: "client_id",
      client_secret: "client secret",
      store: store,
      options: {
        default_version: "v1.0",
      },
    )

    client.get("me")
    assert_requested stub_refresh_token
  end

  def test_client_no_token
    user = User.create(
      access_token: nil,
      refresh_token: "refresh",
      expires_at: 2.hours.ago,
    )

    store = Procore::Auth::Stores::ActiveRecord.new(object: user)
    client = Procore::Client.new(
      client_id: "client_id",
      client_secret: "client secret",
      store: store,
      options: {
        default_version: "v1.0",
      },
    )

    assert_raises(Procore::MissingTokenError) do
      client.get("me")
    end
  end

  def test_client_token_refresh
    stub_refresh_token

    user = User.create(
      access_token: "token",
      refresh_token: "refresh",
      expires_at: 2.hours.from_now,
    )

    store = Procore::Auth::Stores::ActiveRecord.new(object: user)
    client = Procore::Client.new(
      client_id: "client id",
      client_secret: "client secret",
      store: store,
    )

    client.refresh

    assert_requested stub_refresh_token
  end

  def stub_service_account_token(access_token:)
    stub_request(:post, "https://procore-login.example.com/oauth/token")
      .with(body: hash_including("grant_type" => "client_credentials"))
      .to_return(
        status: 200,
        body: { access_token: access_token, token_type: "bearer", expires_in: 7200 }.to_json,
        headers: { "Content-Type" => "application/json" },
      )
  end

  def service_account_client(store)
    Procore::Client.new(
      client_id: "client id",
      client_secret: "client secret",
      store: store,
      grant_type: :client_credentials,
    )
  end

  def test_client_credentials_requests_a_token_when_the_store_is_empty
    token_request = stub_service_account_token(access_token: "service token")
    api_request = stub_request(:get, "https://procore.example.com/rest/v1.0/me")
      .with(headers: { "Authorization" => "Bearer service token" })
    store = Procore::Auth::Stores::Memory.new(key: 1)

    service_account_client(store).get("me")

    assert_requested token_request
    assert_requested api_request
    assert_equal "service token", store.fetch.access_token
  end

  def test_client_credentials_replaces_an_expired_token
    stub_service_account_token(access_token: "new token")
    api_request = stub_request(:get, "https://procore.example.com/rest/v1.0/me")
      .with(headers: { "Authorization" => "Bearer new token" })
    store = Procore::Auth::Stores::Memory.new(key: 1)
    store.save(
      Procore::Auth::Token.new(
        access_token: "old token",
        refresh_token: nil,
        expires_at: 2.hours.ago.to_i,
      ),
    )

    service_account_client(store).get("me")

    assert_requested api_request
  end

  def test_client_credentials_revokes_the_stored_token
    revoke_request = stub_request(:post, "https://procore-login.example.com/oauth/revoke")
      .with(body: hash_including("token" => "service token"))
      .to_return(status: 200)
    store = Procore::Auth::Stores::Memory.new(key: 1)
    store.save(
      Procore::Auth::Token.new(
        access_token: "service token",
        refresh_token: nil,
        expires_at: 2.hours.from_now.to_i,
      ),
    )

    service_account_client(store).revoke

    assert_requested revoke_request
  end

  def test_unknown_grant_type_raises
    error = assert_raises(ArgumentError) do
      Procore::Client.new(
        client_id: "client id",
        client_secret: "client secret",
        store: Procore::Auth::Stores::Memory.new(key: 1),
        grant_type: :password,
      )
    end

    assert_includes error.message, "grant_type"
  end

  def test_client_token_revoke
    stub_revoke_token

    user = User.create(
      access_token: "token",
      refresh_token: "refresh",
      expires_at: 2.hours.from_now,
    )

    store = Procore::Auth::Stores::ActiveRecord.new(object: user)
    client = Procore::Client.new(
      client_id: "client id",
      client_secret: "client secret",
      store: store,
    )

    client.revoke

    assert_requested stub_revoke_token
  end
end
