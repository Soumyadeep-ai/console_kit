# frozen_string_literal: true

module ConsoleKit
  class TenantState
    NO_DROPPED = [].freeze
    EMPTY_UNDO = { context: {}.freeze, backends: {}.freeze, dropped: NO_DROPPED, context_object: nil }.freeze

    attr_reader :tenant_key, :constants, :undo

    module OwnCopy
      class << self
        def call(value)
          case value
          when Hash then value.transform_values { |entry| call(entry) }.freeze
          when Array then value.map { |entry| call(entry) }.freeze
          else value
          end
        end
      end
    end

    class << self
      def empty = new

      def undo_bundle(context:, backends:, dropped: NO_DROPPED, context_object: nil)
        { context: OwnCopy.call(context), backends: OwnCopy.call(backends),
          dropped: OwnCopy.call(dropped), context_object: context_object }.freeze
      end
    end

    def initialize(tenant_key: nil, constants: {}, undo: EMPTY_UNDO, configured: false)
      @tenant_key = tenant_key
      @configured = configured
      @constants = OwnCopy.call(constants)
      @undo = undo
      freeze
    end

    def configured? = @configured
    def undo_context = @undo[:context]
    def undo_backends = @undo[:backends]

    def context_object = @undo[:context_object]

    def dropped_backends = @undo[:dropped] || NO_DROPPED
    def snapshot_for(backend) = @undo[:backends][backend]

    def backends_missing_from(live) = @undo[:backends].keys - live

    def inspect = "#<ConsoleKit::TenantState #{@tenant_key.inspect} backends=#{@undo[:backends].keys.inspect}>"
  end

  module StateStore
    STATE_KEY = :console_kit_state

    class << self
      def current = stored || TenantState.empty

      def stored = Thread.current.thread_variable_get(STATE_KEY)

      def current=(state)
        Thread.current.thread_variable_set(STATE_KEY, state)
      end

      def tenant_key = current.tenant_key
      def configured? = current.configured?

      def clear!
        Thread.current.thread_variable_set(STATE_KEY, nil)
      end
    end
  end
end
