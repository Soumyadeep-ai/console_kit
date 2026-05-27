# lib/console_kit/tenant_resolver/dynamic_strategy.rb
# frozen_string_literal: true

module ConsoleKit
  class TenantResolver
    # Strategy for :dynamic tenant resolution: proc-only, key list is unbounded.
    class DynamicStrategy
      def initialize(resolver_proc) = (@resolver_proc = resolver_proc)

      def all_keys
        raise ConsoleKit::Error, 'all_keys not available in :dynamic mode — tenant list is unbounded'
      end

      def resolve(key) = @resolver_proc&.call(key)
      def any?         = true

      def size
        raise ConsoleKit::Error, 'size not available in :dynamic mode'
      end
    end
  end
end
