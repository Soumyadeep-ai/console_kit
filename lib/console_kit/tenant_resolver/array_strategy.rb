# lib/console_kit/tenant_resolver/array_strategy.rb
# frozen_string_literal: true

module ConsoleKit
  class TenantResolver
    # Strategy for Array-based tenant keys: delegates resolution to a proc.
    class ArrayStrategy
      def initialize(keys, resolver_proc)
        @keys          = keys
        @resolver_proc = resolver_proc
      end

      def all_keys     = @keys
      def resolve(key) = @resolver_proc&.call(key)
      def any?         = @keys.any?
      def size         = @keys.size
    end
  end
end
