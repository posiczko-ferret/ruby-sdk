require "oauth2"
require "procore/errors"

module Procore
  module Auth
    # Shared by the credential classes: builds the OAuth2 client for the
    # login host and revokes tokens through it. Including classes expose
    # +client_id+, +client_secret+ and +host+.
    module OAuthClient
      # @param token [Procore::Auth::Token] the token to revoke. Procore
      #   revokes the matching refresh token as well.
      # @raise [OAuthError] if the revoke request fails.
      def revoke(token:)
        request = {
          client_id: client_id,
          client_secret: client_secret,
          token: token.access_token,
        }
        client.request(:post, "/oauth/revoke", body: request)
      rescue OAuth2::Error => e
        raise OAuthError.new(e.description, response: e.response)
      end

      private

      def client
        OAuth2::Client.new(
          client_id,
          client_secret,
          site: host,
          auth_scheme: :request_body,
        )
      end
    end
  end
end
