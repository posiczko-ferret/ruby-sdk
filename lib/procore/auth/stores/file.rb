require "yaml/store"
require "procore/auth/token"

module Procore
  module Auth
    module Stores
      class File
        # YAML::Store only permits Symbol when loading on Ruby 3.4+, which
        # rejects the serialized Token. Allow the classes a token file holds.
        class TokenStore < YAML::Store
          PERMITTED_CLASSES = [Symbol, Time, Procore::Auth::Token].freeze

          def load(content)
            YAML.safe_load(content, permitted_classes: PERMITTED_CLASSES) || {}
          end
        end

        attr_reader :key, :path
        def initialize(key:, path:)
          @key = key
          @path = path
          @store = TokenStore.new(path)
        end

        def save(token)
          @store.transaction { @store[key] = token }
        end

        def fetch
          @store.transaction { @store[key] }
        end

        def delete
          @store.transaction { @store.delete(key) }
        end

        def to_s
          "File, Key: #{key}, Path: #{path}"
        end
      end
    end
  end
end
