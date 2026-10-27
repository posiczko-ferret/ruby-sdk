require "json"

module Procore
  module Auth
    class Token
      attr_reader :access_token, :refresh_token, :expires_at
      def initialize(access_token:, refresh_token:, expires_at:)
        @access_token = access_token
        @refresh_token = refresh_token
        @expires_at = expires_at
      end

      # The shape the Session, Redis and Dalli stores persist and read back.
      #
      # @return [Hash{Symbol => Object}]
      def to_h
        {
          access_token: access_token,
          refresh_token: refresh_token,
          expires_at: expires_at,
        }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      def invalid?
        access_token.nil?
      end

      def expired?
        expires_at.to_i < Time.now.to_i
      end
    end
  end
end
