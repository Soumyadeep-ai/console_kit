# lib/console_kit/tenant_resolver/hash_strategy.rb
# frozen_string_literal: true

module ConsoleKit
  class TenantResolver
    # Strategy for Hash-based tenant configs: direct key lookup.
    class HashStrategy
      def initialize(hash)       = (@hash = hash)
      def all_keys               = @hash.keys

      def resolve(key)
        @hash[key] || @hash[key.to_s] || @hash[key.to_sym]
      end

      def any?                   = @hash.any?
      def size                   = @hash.size
    end
  end
end
