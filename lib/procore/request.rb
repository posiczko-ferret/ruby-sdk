module Procore
  # The request that produced a Response. Exposes the same values callers read
  # from RestClient::Request before the gem moved to Faraday.
  #
  # @example
  #   response = client.get("projects", query: { per_page: 5 })
  #   response.request.url    #=> "https://api.procore.com/rest/v1.0/projects?per_page=5"
  #   response.request.method #=> "get"
  #
  # @!attribute [r] method
  #   @return [String] HTTP method, lowercase.
  # @!attribute [r] url
  #   @return [String] Full URL, including the query string.
  # @!attribute [r] headers
  #   @return [Hash<String, String>] Request headers as sent.
  # @!attribute [r] payload
  #   @return [String, nil] Request body, or nil when there was none or it was
  #     a multipart upload.
  Request = Struct.new(:method, :url, :headers, :payload, keyword_init: true)
end
