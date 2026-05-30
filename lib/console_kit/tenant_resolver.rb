# lib/console_kit/tenant_resolver.rb
# frozen_string_literal: true

require_relative 'tenant_resolver/hash_strategy'
require_relative 'tenant_resolver/array_strategy'
require_relative 'tenant_resolver/dynamic_strategy'

module ConsoleKit
  # Resolves tenant configuration using one of three strategies:
  # Hash (direct lookup), Array + proc, or :dynamic (proc-only, unbounded keys).
  class TenantResolver
    class << self
      def build(tenants, resolver_proc)
        strategy = case tenants
                   when Hash     then HashStrategy.new(tenants)
                   when Array    then ArrayStrategy.new(tenants.map(&:to_sym), resolver_proc)
                   when :dynamic then DynamicStrategy.new(resolver_proc)
                   else raise Error, "unsupported tenants format: #{tenants.class}"
                   end
        new(strategy)
      end
    end

    def initialize(strategy)  = (@strategy = strategy)
    def all_keys              = @strategy.all_keys
    def resolve(key)          = @strategy.resolve(key)
    def any?                  = @strategy.any?
    def size                  = @strategy.size
  end
end
