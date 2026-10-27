require "active_support/core_ext/hash/deep_merge"
require "faraday"
require "faraday/multipart"
require "faraday/retry"
require "mime/types"
require "procore/errors"
require "procore/request"

module Procore
  # Module which defines HTTP verbs GET, POST, PUT, PATCH and DELETE. Is
  # included in Client. Has support for Idempotency Tokens on POST and PATCH.
  #
  # @example Using #get:
  #   client.get("my_open_items", per_page: 5)
  #
  # @example Using #post:
  #   client.post("projects", name: "New Project")
  module Requestable
    # Failures raised as APIConnectionError once retries are used up.
    HTTP_EXCEPTIONS = [
      Faraday::ConnectionFailed,
      Faraday::SSLError,
      Faraday::TimeoutError,
      Procore::OAuthError,
    ].freeze

    # Connection failures worth retrying: the connection timed out, or the
    # server refused, reset or closed it. DNS, unreachable-host and TLS
    # failures are not retried. faraday-net_http raises connect timeouts
    # (Net::OpenTimeout) as ConnectionFailed, hence Timeout::Error here.
    RETRIABLE_CONNECTION_ERRORS = [
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      EOFError,
      Timeout::Error,
    ].freeze

    RETRY_IF = lambda do |_env, exception|
      if exception.is_a?(Faraday::ConnectionFailed)
        RETRIABLE_CONNECTION_ERRORS.any? do |error|
          exception.wrapped_exception.is_a?(error)
        end
      else
        true
      end
    end
    private_constant :RETRIABLE_CONNECTION_ERRORS, :RETRY_IF

    # GET follows redirects, as it did with rest-client.
    REDIRECT_STATUSES = [301, 302, 303, 307, 308].freeze
    MAX_REDIRECTS = 10
    private_constant :REDIRECT_STATUSES, :MAX_REDIRECTS

    # @param path [String] URL path
    # @param version [String] API version
    # @param query [Hash] Query options to pass along with the request
    # @option options [Hash] :company_id
    #
    # @example Usage
    #   client.get("my_open_items", query: { per_page: 5, filter: {} })
    #
    # @return [Response]
    def get(path, version: nil, query: {}, options: {})
      full_path = full_path(path, version)

      Util.log_info(
        "API Request Initiated",
        path: full_path,
        method: "GET",
        query: query.to_s,
      )

      with_response_handling do
        get_following_redirects(full_path, query, headers(options))
      end
    end

    # @param path [String] URL path
    # @param version [String] API version
    # @param body [Hash] Body parameters to send with the request
    # @param options [Hash] Extra request options
    # @option options [String] :idempotency_token | :company_id
    #
    # @example Usage
    #   client.post(
    #     "users",
    #     body: { name: "New User" },
    #     options: { idempotency_token: "key", company_id: 1 },
    #   )
    #
    # @return [Response]
    def post(path, version: nil, body: {}, options: {})
      full_path = full_path(path, version)

      Util.log_info(
        "API Request Initiated",
        path: full_path,
        method: "POST",
        body: body.to_s,
      )

      with_response_handling(request_body: body) do
        perform(:post, full_path, body: payload(body), headers: headers(options))
      end
    end

    # @param path [String] URL path
    # @param version [String] API version
    # @param body [Hash] Body parameters to send with the request
    # @param options [Hash] Extra request options
    # @option options [String] :idempotency_token | :company_id
    #
    # @example Usage
    #   client.put("dashboards/1/users", body: [1,2,3], options: { company_id: 1 })
    #
    # @return [Response]
    def put(path, version: nil, body: {}, options: {})
      full_path = full_path(path, version)

      Util.log_info(
        "API Request Initiated",
        path: full_path,
        method: "PUT",
        body: body.to_s,
      )

      with_response_handling(request_body: body) do
        perform(:put, full_path, body: payload(body), headers: headers(options))
      end
    end

    # @param path [String] URL path
    # @param version [String] API version
    # @param body [Hash] Body parameters to send with the request
    # @param options [Hash] Extra request options
    # @option options [String] :idempotency_token | :company_id
    #
    # @example Usage
    #   client.patch(
    #     "users/1",
    #     body: { name: "Updated" },
    #     options: { idempotency_token: "key", company_id: 1 },
    #   )
    #
    # @return [Response]
    def patch(path, version: nil, body: {}, options: {})
      full_path = full_path(path, version)

      Util.log_info(
        "API Request Initiated",
        path: full_path,
        method: "PATCH",
        body: body.to_s,
      )

      with_response_handling(request_body: body) do
        perform(:patch, full_path, body: payload(body), headers: headers(options))
      end
    end

    # @param path [String] URL path
    # @param version [String] API version
    # @param body [Hash] Body parameters to send with the request
    # @param options [Hash] Extra request options
    # @option options [String | Integer] :company_id | :batch_size
    #
    # @example Usage
    #   client.sync(
    #     "projects/sync",
    #     body: {
    #       updates: [
    #        { id: 1, name: "Update 1" },
    #        { id: 2, name: "Update 2" },
    #        { id: 3, name: "Update 3" },
    #        ...
    #        ...
    #        { id: 5055, name: "Update 5055" },
    #       ]
    #     },
    #     options: { batch_size: 500, company_id: 1 },
    #   )
    #
    # @return [Response]
    def sync(path, version: nil, body: {}, options: {})
      full_path = full_path(path, version)

      batch_size = options[:batch_size] ||
        Procore.configuration.default_batch_size

      if batch_size > 1000
        batch_size = 1000
      end

      Util.log_info(
        "API Request Initiated",
        path: full_path,
        method: "SYNC",
        batch_size: batch_size,
      )

      groups = body[:updates].each_slice(batch_size).to_a

      responses = groups.map do |group|
        batched_body = body.merge(updates: group)
        with_response_handling(request_body: batched_body) do
          perform(
            :patch,
            full_path,
            body: payload(batched_body),
            headers: headers(options),
          )
        end
      end

      Procore::Response.new(
        body: responses.reduce({}) do |combined, response|
          combined.deep_merge(response.body) { |_, v1, v2| v1 + v2 }
        end.to_json,
        headers: responses.map(&:headers).inject({}, &:deep_merge),
        code: 200,
        request: responses.last&.request,
        request_body: body,
      )
    end

    # @param path [String] URL path
    # @param version [String] API version
    # @param query [Hash] Query options to pass along with the request
    # @option options [String] :company_id
    #
    # @example Usage
    #   client.delete("users/1", query: {}, options: {})
    #
    # @return [Response]
    def delete(path, version: nil, query: {}, options: {})
      full_path = full_path(path, version)

      Util.log_info(
        "API Request Initiated",
        path: full_path,
        method: "DELETE",
        query: query.to_s,
      )

      with_response_handling do
        perform(:delete, full_path, params: query, headers: headers(options))
      end
    end

    private

    def with_response_handling(request_body: nil)
      request_start_time = Time.now
      retries = 0

      begin
        result = yield
      rescue Procore::OAuthError
        # The access token is fetched before Faraday sends the request, so the
        # retry middleware never sees this failure. Retry it here instead.
        if retries < Procore.configuration.max_retries
          retries += 1
          sleep 1.5**retries
          retry
        else
          raise_connection_error
        end
      rescue *HTTP_EXCEPTIONS
        raise_connection_error
      end

      response = build_response(result, request_body)

      case response.code
      when 200..299
        Util.log_info(
          "API Request Finished ",
          path: response.request.url,
          status: response.code.to_s,
          duration: "#{((Time.now - request_start_time) * 1000).round(0)}ms",
          request_id: response.headers[:x_request_id],
        )
      else
        Util.log_error(
          "API Request Failed",
          path: response.request.url,
          status: response.code.to_s,
          duration: "#{((Time.now - request_start_time) * 1000).round(0)}ms",
          request_id: response.headers[:x_request_id],
          retries: retries,
        )
      end

      case response.code
      when 200..299
        response
      when 401
        raise Procore::AuthorizationError.new(
          "The request failed because you lack the correct credentials to "    \
          "access the target resource",
          response: response,
        )
      when 403
        raise Procore::ForbiddenError.new(
          "The request failed because you lack the required permissions",
          response: response,
        )
      when 404
        raise Procore::NotFoundError.new(
          "The URI requested is invalid or the resource requested does not "   \
          "exist.",
          response: response,
        )
      when 400, 422
        raise Procore::InvalidRequestError.new(
          "Bad Request.",
          response: response,
        )
      when 429
        raise Procore::RateLimitError.new(
          "You have surpassed the max number of requests for an hour. Please " \
          "wait until your limit resets.",
          response: response,
        )
      else
        raise Procore::ServerError.new(
          "Something is broken. This is usually a temporary error - Procore "  \
          "may be down or this endpoint may be having issues. Check "          \
          "http://status.procore.com for any known or ongoing issues.",
          response: response,
        )
      end
    end

    def headers(options = {})
      {
        "Accepts" => "application/json",
        "Authorization" => "Bearer #{access_token}",
        "Content-Type" => "application/json",
        "Procore-Sdk-Version" => Procore::VERSION,
        "Procore-Sdk-Language" => "ruby",
        "User-Agent" => Procore.configuration.user_agent,
      }.tap do |headers|
        if options[:idempotency_token]
          headers["Idempotency-Token"] = options[:idempotency_token].to_s
        end

        if options[:company_id]
          headers["procore-company-id"] = options[:company_id].to_s
        end
      end
    end

    # Raised from inside a rescue, so the original error becomes the cause.
    def raise_connection_error
      raise APIConnectionError.new(
        "Cannot connect to the Procore API. Double check your timeout "    \
        "settings to ensure requests are not being cancelled before they " \
        "can complete. Try setting the timeout and max_retries to larger " \
        "values.",
      )
    end

    def connection
      Faraday.new do |conn|
        conn.options.timeout = Procore.configuration.timeout
        # Retry runs before multipart so each attempt re-encodes the upload.
        conn.request :retry,
          max: Procore.configuration.max_retries,
          interval: 1.5,
          backoff_factor: 1.5,
          exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed],
          methods: [],
          retry_if: RETRY_IF
        conn.request :multipart
        conn.adapter Faraday.default_adapter
      end
    end

    def perform(method, url, headers:, params: nil, body: nil)
      # Multipart bodies arrive as a Hash; let the middleware set the
      # multipart Content-Type and boundary.
      if body.is_a?(Hash)
        headers = headers.except("Content-Type")
      end

      connection.run_request(method, url, body, headers) do |request|
        request.params.update(params) if params
      end
    end

    def get_following_redirects(url, query, headers)
      response = perform(:get, url, params: query, headers: headers)
      MAX_REDIRECTS.times do
        location = response.headers["location"]
        break unless REDIRECT_STATUSES.include?(response.status) && location

        response = perform(
          :get,
          URI.join(response.env.url.to_s, location).to_s,
          headers: headers,
        )
      end
      response
    end

    def build_response(result, request_body)
      env = result.env

      Procore::Response.new(
        body: result.body,
        headers: response_headers(result.headers),
        code: result.status,
        request: Procore::Request.new(
          method: env.method.to_s,
          url: env.url.to_s,
          headers: env.request_headers.to_h,
          payload: (env.request_body if env.request_body.is_a?(String)),
        ),
        request_body: request_body,
      )
    end

    # Keys headers the way rest-client did (:x_request_id, :content_type),
    # which callers and Response#pagination rely on.
    def response_headers(headers)
      headers.to_h.to_h do |name, value|
        [name.to_s.downcase.tr("-", "_").to_sym, value]
      end
    end

    def payload(body)
      if multipart?(body)
        multipart_body(body)
      else
        body.to_json
      end
    end

    def multipart?(body)
      case body
      when Hash then body.values.any? { |value| multipart?(value) }
      when Array then body.any? { |value| multipart?(value) }
      else file?(body)
      end
    end

    def multipart_body(body)
      case body
      when Hash then body.transform_values { |value| multipart_body(value) }
      when Array then body.map { |value| multipart_body(value) }
      else
        if file?(body)
          Faraday::Multipart::FilePart.new(
            body,
            content_type(body.path),
            File.basename(body.path),
          )
        else
          body
        end
      end
    end

    # Guesses from the file extension, as rest-client did.
    def content_type(path)
      MIME::Types.type_for(path).first&.content_type ||
        "application/octet-stream"
    end

    def file?(value)
      value.respond_to?(:path) && value.respond_to?(:read)
    end

    def full_path(path, version)
      version ||= options[:default_version]
      if version == "vapid"
        File.join(base_api_path, "vapid", path)
      elsif /\Av\d+\.\d+\z/.match?(version)
        File.join(base_api_path, "rest", version, path)
      else
        raise Procore::InvalidRequestError.new "#{version} is an invalid Procore API version"
      end
    end
  end
end
