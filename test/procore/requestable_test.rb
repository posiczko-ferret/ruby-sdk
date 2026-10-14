require "test_helper"

class Procore::RequestableTest < Minitest::Test
  class Request
    include Procore::Requestable

    attr_reader :access_token

    def initialize(token:)
      @access_token = token
    end

    def base_api_path
      "http://test.com"
    end

    def options
      {
        default_version: "v1.0",
      }
    end
  end

  def with_max_retries(count)
    max_retries_old = Procore.configuration.max_retries
    Procore.configuration.max_retries = count
    yield
  ensure
    Procore.configuration.max_retries = max_retries_old
  end

  # Runs the block with retry backoff recorded instead of slept.
  #
  # @return [Array<Float>] the waits requested, in order
  def record_sleeps(request)
    sleeps = []
    request.stub(:sleep, ->(seconds) { sleeps << seconds }) do
      yield
    end
    sleeps
  end

  def headers
    {
      "Accepts" => "application/json",
      "Authorization" => "Bearer token",
      "Content-Type" => "application/json",
      "Procore-Sdk-Version" => Procore::VERSION,
      "Procore-Sdk-Language" => "ruby",
    }
  end

  def test_get
    request = stub_request(:get, "http://test.com/rest/v1.0/home")
      .with(
        query: { per_page: 5 },
        headers: headers
      )
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").get("home", query: { per_page: 5 })

    assert_requested request
  end

  def test_rest_get
    request = stub_request(:get, "http://test.com/rest/v1.1/home")
      .with(
        query: { per_page: 5 },
        headers: headers
      )
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").get("home", version: "v1.1", query: { per_page: 5 })

    assert_requested request
  end

  def test_vapid_get
    request = stub_request(:get, "http://test.com/vapid/home")
      .with(
        query: { per_page: 5 },
        headers: headers
      )
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").get("home", version: "vapid", query: { per_page: 5 })

    assert_requested request
  end

  def test_post
    request = stub_request(:post, "http://test.com/rest/v1.0/home")
      .with(
        body: { name: "Name" },
        headers: headers
      )
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").post("home", body: { name: "Name" })

    assert_requested request
  end

  def test_rest_post
    request = stub_request(:post, "http://test.com/rest/v1.1/home")
      .with(
        body: { name: "Name" },
        headers: headers
      )
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").post("home", version: "v1.1", body: { name: "Name" })

    assert_requested request
  end

  def test_vapid_post
    request = stub_request(:post, "http://test.com/vapid/home")
      .with(
        body: { name: "Name" },
        headers: headers
      )
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").post("home", version: "vapid", body: { name: "Name" })

    assert_requested request
  end

  def test_put
    request = stub_request(:put, "http://test.com/rest/v1.0/home")
      .with(
        body: { name: "Replaced Name" },
        headers: headers
      )
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").put("home", body: { name: "Replaced Name" })

    assert_requested request
  end

  def test_rest_put
    request = stub_request(:put, "http://test.com/rest/v1.1/home")
      .with(
        body: { name: "Replaced Name" },
        headers: headers
      )
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").put("home", version: "v1.1", body: { name: "Replaced Name" })

    assert_requested request
  end


  def test_vapid_put
    request = stub_request(:put, "http://test.com/vapid/home")
      .with(
        body: { name: "Replaced Name" },
        headers: headers
      )
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").put("home", version: "vapid", body: { name: "Replaced Name" })

    assert_requested request
  end

  def test_patch
    request = stub_request(:patch, "http://test.com/rest/v1.0/home")
      .with(
        body: { name: "New Name" },
        headers: headers
      )
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").patch("home", body: { name: "New Name" })

    assert_requested request
  end

  def test_delete
    request = stub_request(:delete, "http://test.com/rest/v1.0/home")
      .with(headers: headers)
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").delete("home")

    assert_requested request
  end

  def test_sync
    update1 = [{ id: 4, name: "Updated Project 4" }]
    request1 = stub_request(:patch, "http://test.com/rest/v1.0/projects/sync")
      .with(body: { company_id: 13, updates: update1 })
      .to_return(
        status: 200,
        body: {
          entities: [{ id: 4, name: "Updated Project 4" }],
          errors: [],
        }.to_json,
        headers: {},
      )

    update2 = [{ id: 0, name: "Updated Project 0" }]
    request2 = stub_request(:patch, "http://test.com/rest/v1.0/projects/sync")
      .with(body: { company_id: 13, updates: update2 }).to_return(
        status: 200,
        body: {
          entities: [],
          errors: [{
            id: 0,
            name: "No project has this id value",
            errors: { id: ["Entity with this ID not found"] },
          }],
        }.to_json,
        headers: {},
      )

    response = Request.new(token: "token").sync(
      "projects/sync",
      body: { company_id: 13, updates: update1 + update2 },
      options: { batch_size: 1 },
    )

    assert_requested request1
    assert_requested request2

    expected_body = {
      entities: [{ id: 4, name: "Updated Project 4" }],
      errors: [{
        id: 0,
        name: "No project has this id value",
        errors: { id: ["Entity with this ID not found"] },
      }],
    }
    assert_equal expected_body.deep_stringify_keys, response.body
  end

  def test_post_with_idempotency_token
    request = stub_request(:post, "http://test.com/rest/v1.0/home")
      .with(
        headers: headers.merge("Idempotency-Token" => "token"),
      )
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").post(
      "home",
      body: {},
      options: { idempotency_token: "token" },
    )

    assert_requested request
  end

  def test_get_with_company_id
    request = stub_request(:get, "http://test.com/rest/v1.0/home")
      .with(
        headers: headers.merge("procore-company-id" => "1")
      )
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").get(
      "home",
      options: { company_id: 1 },
    )

    assert_requested request
  end

  def test_post_with_company_id
    request = stub_request(:post, "http://test.com/rest/v1.0/home")
      .with(
        body: { name: "Name" },
        headers: headers.merge("procore-company-id" => "1"),
      )
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").post(
      "home",
      body: { name: "Name" },
      options: { company_id: 1 },
    )

    assert_requested request
  end

  def test_delete_with_company_id
    request = stub_request(:delete, "http://test.com/rest/v1.0/home")
      .with(
        headers: headers.merge("procore-company-id" => "1")
      )
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").delete(
      "home",
      options: { company_id: 1 },
    )

    assert_requested request
  end

  def test_delete_does_not_log_access_token
    stub_request(:delete, "http://test.com/rest/v1.0/home")
      .to_return(status: 200, body: "", headers: {})
    output = StringIO.new
    logger_old = Procore.configuration.logger
    Procore.configuration.logger = Logger.new(output)

    begin
      Request.new(token: "secret-token").delete("home")
    ensure
      Procore.configuration.logger = logger_old
    end

    refute_includes output.string, "secret-token"
  end

  def test_post_with_multipart_body
    request = stub_request(:post, "http://test.com/rest/v1.0/home")
      .with(
        headers: headers.merge("Content-Type" => %r[multipart/form-data]),
      )
      .to_return(status: 200, body: "", headers: {})

    pixel = File.new("test/support/pixel.png", "r")

    Request.new(token: "token").post("home", body: { file: pixel })

    assert_requested request
  end

  def test_unauthorized_error
    stub_request(:get, "http://test.com/rest/v1.0/")
      .to_return(status: 401, body: "", headers: {})

    assert_raises Procore::AuthorizationError do
      Request.new(token: "token").get("")
    end
  end

  def test_forbidden_error
    stub_request(:get, "http://test.com/rest/v1.0/")
      .to_return(status: 403, body: "", headers: {})

    assert_raises Procore::ForbiddenError do
      Request.new(token: "token").get("")
    end
  end

  def test_not_found_error
    stub_request(:get, "http://test.com/rest/v1.0/")
      .to_return(status: 404, body: "", headers: {})

    assert_raises Procore::NotFoundError do
      Request.new(token: "token").get("")
    end
  end

  def test_server_error
    stub_request(:get, "http://test.com/rest/v1.0/")
      .to_return(status: 500, body: "", headers: {})

    assert_raises Procore::ServerError do
      Request.new(token: "token").get("")
    end
  end

  def test_error_body
    stub_request(:get, "http://test.com/rest/v1.0/")
      .to_return(
        status: 401,
        body: { errors: "Unauthorized" }.to_json,
        headers: {},
      )

    error = assert_raises Procore::AuthorizationError do
      Request.new(token: "token").get("")
    end

    assert_equal({ "errors" => "Unauthorized" }, error.response.body)
  end

  def test_no_retry_logic
    # Disable retries
    max_retries_old = Procore.configuration.max_retries

    begin
      Procore.configuration.max_retries = 0
      stub_request(:get, "http://test.com/rest/v1.0/retry_test")
        .to_timeout

      # Attempt to perform the request and assert the correct exception is raised
      assert_raises(Procore::APIConnectionError) do
        Request.new(token: "token").get("retry_test")
      end

      assert_requested :get, "http://test.com/rest/v1.0/retry_test", times: 1
    ensure
      Procore.configuration.max_retries = max_retries_old
    end
  end

  def test_get_encodes_nested_query
    request = stub_request(:get, "http://test.com/rest/v1.0/home")
      .with(query: { filters: { status: "open", ids: [1, 2] }, per_page: 5 })
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").get(
      "home",
      query: { filters: { status: "open", ids: [1, 2] }, per_page: 5 },
    )

    assert_requested request
  end

  def test_delete_with_query
    request = stub_request(:delete, "http://test.com/rest/v1.0/home")
      .with(query: { force: true }, headers: headers)
      .to_return(status: 200, body: "", headers: {})

    Request.new(token: "token").delete("home", query: { force: true })

    assert_requested request
  end

  def test_post_multipart_sends_file_and_fields
    request = stub_request(:post, "http://test.com/rest/v1.0/home")
      .with { |req|
        req.body.include?('name="file"; filename="pixel.png"') &&
          req.body.include?('name="description"') &&
          req.body.include?("A pixel")
      }
      .to_return(status: 200, body: "", headers: {})

    pixel = File.new("test/support/pixel.png", "r")

    Request.new(token: "token").post(
      "home",
      body: { file: pixel, description: "A pixel" },
    )

    assert_requested request
  end

  def test_response_headers_use_symbol_keys
    stub_request(:get, "http://test.com/rest/v1.0/home")
      .to_return(
        status: 200,
        body: "",
        headers: { "X-Request-Id" => "abc", "Content-Type" => "application/json" },
      )

    response = Request.new(token: "token").get("home")

    assert_equal "abc", response.headers[:x_request_id]
    assert_equal "application/json", response.headers[:content_type]
  end

  def test_response_pagination_from_link_header
    stub_request(:get, "http://test.com/rest/v1.0/projects")
      .to_return(
        status: 200,
        body: "[]",
        headers: {
          "Link" => '<http://test.com/rest/v1.0/projects?page=2>; rel="next", ' \
            '<http://test.com/rest/v1.0/projects?page=9>; rel="last"',
        },
      )

    response = Request.new(token: "token").get("projects")

    assert_equal(
      { next: "projects?page=2", last: "projects?page=9" },
      response.pagination,
    )
  end

  def test_response_exposes_code_request_and_request_body
    stub_request(:post, "http://test.com/rest/v1.0/home")
      .to_return(status: 201, body: { id: 1 }.to_json, headers: {})

    response = Request.new(token: "token").post("home", body: { name: "Name" })

    assert_equal 201, response.code
    assert_equal({ "id" => 1 }, response.body)
    assert_equal({ name: "Name" }, response.request_body)
    assert_equal "http://test.com/rest/v1.0/home", response.request.url
    assert_equal "post", response.request.method.to_s
  end

  # Response#request keeps the values RestClient::Request gave callers.
  def test_response_request_matches_rest_client_values
    stub_request(:get, "http://test.com/rest/v1.0/home")
      .with(query: { per_page: 5 })
      .to_return(status: 200, body: "", headers: {})

    request = Request.new(token: "token").get("home", query: { per_page: 5 }).request

    assert_equal "http://test.com/rest/v1.0/home?per_page=5", request.url
    assert_equal "get", request.method
    assert_equal "Bearer token", request.headers["Authorization"]
  end

  def test_sync_caps_batch_size_at_1000
    updates = (1..1001).map { |id| { id: id } }
    stub_request(:patch, "http://test.com/rest/v1.0/projects/sync")
      .to_return(status: 200, body: { entities: [], errors: [] }.to_json)

    Request.new(token: "token").sync(
      "projects/sync",
      body: { updates: updates },
      options: { batch_size: 5000 },
    )

    assert_requested :patch, "http://test.com/rest/v1.0/projects/sync", times: 2
  end

  def test_invalid_version_raises
    assert_raises Procore::InvalidRequestError do
      Request.new(token: "token").get("home", version: "v1")
    end
  end

  def test_bad_request_error
    stub_request(:get, "http://test.com/rest/v1.0/")
      .to_return(status: 400, body: "", headers: {})

    error = assert_raises Procore::InvalidRequestError do
      Request.new(token: "token").get("")
    end

    assert_equal 400, error.response.code
  end

  def test_unprocessable_entity_error
    stub_request(:get, "http://test.com/rest/v1.0/")
      .to_return(status: 422, body: "", headers: {})

    error = assert_raises Procore::InvalidRequestError do
      Request.new(token: "token").get("")
    end

    assert_equal 422, error.response.code
  end

  def test_rate_limit_error
    stub_request(:get, "http://test.com/rest/v1.0/")
      .to_return(status: 429, body: "", headers: {})

    error = assert_raises Procore::RateLimitError do
      Request.new(token: "token").get("")
    end

    assert_equal 429, error.response.code
  end

  def test_retries_timeout_with_backoff_then_raises
    stub_request(:get, "http://test.com/rest/v1.0/retry_test").to_timeout
    request = Request.new(token: "token")

    sleeps = with_max_retries(2) do
      record_sleeps(request) do
        assert_raises(Procore::APIConnectionError) do
          request.get("retry_test")
        end
      end
    end

    assert_requested :get, "http://test.com/rest/v1.0/retry_test", times: 3
    assert_equal [1.5, 2.25], sleeps
  end

  def test_retry_succeeds_after_transient_failure
    stub_request(:get, "http://test.com/rest/v1.0/retry_test")
      .to_timeout
      .then
      .to_return(status: 200, body: { ok: true }.to_json, headers: {})

    request = Request.new(token: "token")

    response = nil

    with_max_retries(1) do
      record_sleeps(request) do
        response = request.get("retry_test")
      end
    end

    assert_equal({ "ok" => true }, response.body)
    assert_requested :get, "http://test.com/rest/v1.0/retry_test", times: 2
  end

  def test_retries_connection_refused
    stub_request(:get, "http://test.com/rest/v1.0/retry_test")
      .to_raise(Errno::ECONNREFUSED)
    request = Request.new(token: "token")

    with_max_retries(1) do
      record_sleeps(request) do
        assert_raises(Procore::APIConnectionError) do
          request.get("retry_test")
        end
      end
    end

    assert_requested :get, "http://test.com/rest/v1.0/retry_test", times: 2
  end

  def test_retries_connection_reset
    stub_request(:get, "http://test.com/rest/v1.0/retry_test")
      .to_raise(Errno::ECONNRESET)
    request = Request.new(token: "token")

    with_max_retries(1) do
      record_sleeps(request) do
        assert_raises(Procore::APIConnectionError) do
          request.get("retry_test")
        end
      end
    end

    assert_requested :get, "http://test.com/rest/v1.0/retry_test", times: 2
  end

  def test_post_is_retried
    stub_request(:post, "http://test.com/rest/v1.0/retry_test").to_timeout
    request = Request.new(token: "token")

    with_max_retries(1) do
      record_sleeps(request) do
        assert_raises(Procore::APIConnectionError) do
          request.post("retry_test", body: { name: "Name" })
        end
      end
    end

    assert_requested :post, "http://test.com/rest/v1.0/retry_test", times: 2
  end

  def test_patch_is_retried
    stub_request(:patch, "http://test.com/rest/v1.0/retry_test").to_timeout
    request = Request.new(token: "token")

    with_max_retries(1) do
      record_sleeps(request) do
        assert_raises(Procore::APIConnectionError) do
          request.patch("retry_test", body: { name: "Name" })
        end
      end
    end

    assert_requested :patch, "http://test.com/rest/v1.0/retry_test", times: 2
  end

  def test_server_error_is_not_retried
    stub_request(:get, "http://test.com/rest/v1.0/retry_test")
      .to_return(status: 500, body: "", headers: {})

    with_max_retries(2) do
      assert_raises(Procore::ServerError) do
        Request.new(token: "token").get("retry_test")
      end
    end

    assert_requested :get, "http://test.com/rest/v1.0/retry_test", times: 1
  end

  def test_rate_limit_is_not_retried
    stub_request(:get, "http://test.com/rest/v1.0/retry_test")
      .to_return(status: 429, body: "", headers: {})

    with_max_retries(2) do
      assert_raises(Procore::RateLimitError) do
        Request.new(token: "token").get("retry_test")
      end
    end

    assert_requested :get, "http://test.com/rest/v1.0/retry_test", times: 1
  end

  def test_access_token_failure_is_retried
    request = stub_request(:get, "http://test.com/rest/v1.0/home")
      .to_return(status: 200, body: "", headers: {})
    client = Request.new(token: "token")
    token_attempts = 0
    flaky_token = -> {
      token_attempts += 1
      if token_attempts == 1
        raise Procore::OAuthError.new("Token refresh failed")
      else
        "token"
      end
    }

    with_max_retries(1) do
      record_sleeps(client) do
        client.stub(:access_token, flaky_token) do
          client.get("home")
        end
      end
    end

    assert_requested request, times: 1
  end
end
