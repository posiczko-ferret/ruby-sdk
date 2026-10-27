require "test_helper"

# The HTTP library behind Procore::Requestable is an implementation detail.
# These tests fail when rest-client types reach callers of the client, and pin
# rest-client behaviour that callers rely on. See
# docs/adr/0001-replace-rest-client-with-faraday.md.
class Procore::RestClientLeakageTest < Minitest::Test
  class Request
    include Procore::Requestable

    def access_token
      "token"
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

  def setup
    @max_retries_old = Procore.configuration.max_retries
    Procore.configuration.max_retries = 0
  end

  def teardown
    Procore.configuration.max_retries = @max_retries_old
  end

  def assert_not_rest_client(object)
    refute object.class.name.to_s.start_with?("RestClient"),
      "#{object.class} leaked to the caller"
  end

  def test_response_request_is_not_a_rest_client_object
    stub_request(:get, "http://test.com/rest/v1.0/home")
      .to_return(status: 200, body: "", headers: {})

    response = Request.new.get("home")

    assert_not_rest_client response.request
  end

  def test_error_response_request_is_not_a_rest_client_object
    stub_request(:get, "http://test.com/rest/v1.0/home")
      .to_return(status: 404, body: "", headers: {})

    error = assert_raises Procore::NotFoundError do
      Request.new.get("home")
    end

    assert_not_rest_client error.response.request
  end

  def test_response_headers_are_a_plain_hash_with_symbol_keys
    stub_request(:get, "http://test.com/rest/v1.0/home")
      .to_return(status: 200, body: "", headers: { "X-Request-Id" => "abc" })

    response = Request.new.get("home")

    assert_instance_of Hash, response.headers
    assert response.headers.keys.all?(Symbol)
  end

  def test_timeout_cause_is_not_a_rest_client_exception
    stub_request(:get, "http://test.com/rest/v1.0/home").to_timeout

    error = assert_raises Procore::APIConnectionError do
      Request.new.get("home")
    end

    assert_not_rest_client error.cause
  end

  def test_broken_connection_cause_is_not_a_rest_client_exception
    stub_request(:get, "http://test.com/rest/v1.0/home").to_raise(EOFError)

    error = assert_raises Procore::APIConnectionError do
      Request.new.get("home")
    end

    assert_not_rest_client error.cause
  end

  def test_ssl_failure_raises_procore_error
    stub_request(:get, "http://test.com/rest/v1.0/home")
      .to_raise(OpenSSL::SSL::SSLError.new("certificate verify failed"))

    assert_raises Procore::APIConnectionError do
      Request.new.get("home")
    end
  end

  def test_dns_failure_raises_procore_error
    stub_request(:get, "http://test.com/rest/v1.0/home").to_raise(SocketError)

    assert_raises Procore::APIConnectionError do
      Request.new.get("home")
    end
  end

  def test_unreachable_host_raises_procore_error
    stub_request(:get, "http://test.com/rest/v1.0/home")
      .to_raise(Errno::EHOSTUNREACH)

    assert_raises Procore::APIConnectionError do
      Request.new.get("home")
    end
  end

  def test_http_exceptions_constant_has_no_rest_client_classes
    names = Procore::Requestable::HTTP_EXCEPTIONS.map(&:name)

    assert_empty names.grep(/\ARestClient\b/)
  end

  def test_requiring_procore_does_not_load_rest_client
    loaded = system(
      RbConfig.ruby,
      "-Ilib",
      "-e",
      'require "procore"; exit(defined?(RestClient) ? 1 : 0)',
    )

    assert loaded, "require \"procore\" defined RestClient"
  end

  # rest-client follows redirects on GET. Faraday does not unless configured,
  # so this pins the behaviour across the switch.
  def test_get_follows_redirects
    stub_request(:get, "http://test.com/rest/v1.0/old")
      .to_return(
        status: 301,
        headers: { "Location" => "http://test.com/rest/v1.0/new" },
      )
    stub_request(:get, "http://test.com/rest/v1.0/new")
      .to_return(status: 200, body: { moved: true }.to_json, headers: {})

    response = Request.new.get("old")

    assert_equal 200, response.code
    assert_equal({ "moved" => true }, response.body)
  end
end
