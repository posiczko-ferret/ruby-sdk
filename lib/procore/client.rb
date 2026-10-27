require "procore/requestable"

module Procore
  # Main class end users interact with. An instance of a client can call out
  # the Procore API using methods matching standard HTTP verbs #get, #post,
  # #put, #patch, #delete.
  #
  # @example Creating a new client:
  #   store = Procore::Auth::Stores::Session.new(session: session)
  #   client = Procore::Client.new(
  #     client_id: Rails.application.secrets.procore_client_id,
  #     client_secret: Rails.application.secrets.procore_secret_id,
  #     store: store
  #   )
  #
  #   client.get("me").body #=> { id: 5, email: "person@example.com" }
  class Client
    include Procore::Requestable

    attr_reader :options, :store

    GRANT_TYPES = [:authorization_code, :client_credentials].freeze

    # @param client_id [String] Client ID issued from Procore
    # @param client_secret [String] Client Secret issued from Procore
    # @param store [Auth::Store] A store to use for saving, updating and
    #   refreshing tokens
    # @param grant_type [Symbol] :authorization_code (the default) refreshes
    #   a user's token that the application has already put in the store.
    #   :client_credentials is for service accounts: the client requests its
    #   own token whenever the store is empty or the token has expired.
    # @param options [Hash] options to configure the client with
    # @option options [String] :host Endpoint to use for the API. Defaults to
    #   Configuration.host
    # @option options [String] :login_host used by the OAuth client to generate API tokens.
    # Defaults to Configuration.login_host
    # @option options [String] :user_agent User Agent string to send along with
    #   the request. Defaults to Configuration.user_agent
    def initialize(client_id:, client_secret:, store:, grant_type: :authorization_code, options: {})
      unless GRANT_TYPES.include?(grant_type)
        raise ArgumentError, "grant_type must be one of " \
          "#{GRANT_TYPES.map(&:inspect).join(', ')}, got #{grant_type.inspect}"
      end

      @options = Procore::Defaults::client_options.merge(options)
      @grant_type = grant_type
      @credentials = credentials_class.new(
        client_id: client_id,
        client_secret: client_secret,
        host: @options[:login_host],
      )
      @store = store
    end

    # @raise [OAuthError] if a token cannot be refreshed.
    def refresh
      token = fetch_token

      begin
        new_token = @credentials.refresh(
          token: token&.access_token,
          refresh: token&.refresh_token,
        )

        Util.log_info("Token Refresh Successful", store: store)
        store.save(new_token)
      rescue RuntimeError
        Util.log_error("Token Refresh Failed", store: store)
        raise Procore::OAuthError.new(
          "Unable to refresh the access token. Perhaps the Procore API is "  \
          "down or your access token store is misconfigured. Either "    \
          "way, you should clear the store and prompt the user to sign in "  \
          "again.",
        )
      end
    end

    # @raise [OAuthError] if a token cannot be revoked.
    # @raise [MissingTokenError] if the store holds no token to revoke.
    def revoke
      token = fetch_token
      if token.nil?
        raise Procore::MissingTokenError.new("The store holds no token to revoke.")
      end

      begin
        @credentials.revoke(token: token)
        Util.log_info("Token Revocation Successful", store: store)
      rescue RuntimeError
        Util.log_error("Token Revocation Failed", store: store)
        raise Procore::OAuthError.new(
          "Unable to revoke the access token. Perhaps the Procore API is "  \
          "down or your access token store is misconfigured. Either "    \
          "way, you should clear the store and prompt the user to sign in "  \
          "again.",
        )
      end
    end

    private

    def base_api_path
      "#{options[:host]}"
    end

    def credentials_class
      if @grant_type == :client_credentials
        Procore::Auth::ClientCredentials
      else
        Procore::Auth::AccessTokenCredentials
      end
    end

    # A service account needs nothing in the store up front; the client
    # requests its own token.
    def token_required?
      @grant_type == :authorization_code
    end

    # @return [Auth::Token, nil] nil only when the grant type can request a
    #   token without one.
    # @raise [MissingTokenError] if the store has no usable token and the
    #   grant type needs one.
    def fetch_token
      token = store.fetch
      if token && !token.invalid?
        token
      elsif token_required?
        raise Procore::MissingTokenError.new(
          "Unable to retreive an access token from the store. Double check "   \
          "your store configuration and make sure to correctly store a token " \
          "before attempting to make API requests",
        )
      end
    end

    def access_token
      token = fetch_token
      if token.nil? || token.expired?
        Util.log_info(token.nil? ? "Token Missing" : "Token Expired", store: store)
        refresh
        token = fetch_token
      end
      token.access_token
    end
  end
end
