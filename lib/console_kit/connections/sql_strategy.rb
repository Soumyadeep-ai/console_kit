# frozen_string_literal: true

require_relative '../errors'

module ConsoleKit
  module Connections
    # Rails-version-tolerant plumbing for pointing a SQL base class at a shard.
    #
    # Two strategies are picked per target:
    #
    #   native   - the target is a shard registered through `connects_to shards:`,
    #              so `connecting_to` (Rails 6.1+) is used. It is fiber/thread
    #              local and touches no connection pool.
    #   fallback - the target is a plain database.yml configuration name, so
    #              `establish_connection` is used. It is skipped entirely when
    #              the resolved configuration is already the live one, which is
    #              what keeps repeated switches from churning pools. Rails'
    #              own connection handler disconnects the pool it replaces, so
    #              no extra `disconnect!` is issued here.
    #
    # Every Rails API touched here is feature-detected with `respond_to?`, never
    # by Rails version, so one code path serves Rails 6.1 through 8.0.
    class SqlStrategy
      NATIVE_METHODS = %i[connecting_to connected_to_stack default_shard current_shard current_role].freeze

      # `connecting_to` pushes onto the fiber-local shard stack and Rails offers
      # no matching pop, so every committed switch used to leave one frame
      # behind for the rest of the console session. The frame this fiber pushed
      # is remembered here and dropped before the next one goes on, which holds
      # the stack at a single ConsoleKit frame however many switches happen.
      # Only a frame we pushed, and only while it is still on top, is popped,
      # so a frame the application pushed itself is never disturbed.
      FRAME_KEY = :console_kit_sql_connected_to_frame

      class << self
        # Errors that mean "our own code is wrong" and must never be swallowed.
        def programming_error?(error) = ConsoleKit.programming_error?(error)
      end

      attr_reader :base_class

      def initialize(base_class) = @base_class = base_class

      # --- resolution: reads only, mutates nothing ------------------------

      def switchable? = base_class.respond_to?(:establish_connection) || native_capable?

      # True when `shard` can be reached through Rails' native shard stack.
      # A nil shard means "default": native only matters there if something has
      # already pushed onto the stack, otherwise the pool itself is the default.
      def native?(shard)
        return false unless native_capable?
        return !connected_to_stack.to_a.empty? if shard.nil?

        !shard_pool(shard).nil?
      end

      # Only report a shard unresolvable when we can actually prove it: an
      # unreadable `configurations` is not evidence of a bad shard.
      def resolvable?(shard)
        return true if shard.nil? || native?(shard)

        configs = env_configs
        configs.empty? || configs.any? { |cfg| config_name(cfg).to_s == shard.to_s }
      end

      # --- snapshot / apply / restore -------------------------------------

      def snapshot
        {
          shard: base_class.try(:current_shard),
          role: base_class.try(:current_role),
          stack_depth: connected_to_stack&.size,
          db_config_name: current_db_config_name
        }
      end

      def apply(shard) = native?(shard) ? apply_native(shard) : apply_fallback(shard)

      def restore(state)
        return if state.nil?

        unwind_stack(state[:stack_depth])
        restore_shard(state[:shard])
        reestablish(state[:db_config_name])
      end

      # --- identity --------------------------------------------------------

      # [expected, actual] identity of the live connection. Cheap local reads
      # only: the shard stack on the native path, the pool's db_config name on
      # the fallback path. Never a network round trip.
      def identity(shard)
        return [shard || base_class.default_shard, base_class.current_shard] if native?(shard)

        [expected_db_config_name(shard), current_db_config_name]
      end

      # Network-free description of the resolved connection, for diagnostics.
      def pool_details
        pool = base_class.try(:connection_pool)
        return {} if pool.nil?

        { adapter: pool.try(:db_config).try(:adapter), pool_size: pool.try(:size),
          config: current_db_config_name, shard: base_class.try(:current_shard) }.compact
      rescue StandardError => e
        raise e if self.class.programming_error?(e)

        {}
      end

      private

      def native_capable? = NATIVE_METHODS.all? { |method| base_class.respond_to?(method) }
      def connected_to_stack = base_class.try(:connected_to_stack)

      # Replaces this fiber's ConsoleKit frame rather than stacking another one.
      def apply_native(shard)
        drop_owned_frame
        base_class.connecting_to(shard: shard || base_class.default_shard, role: base_class.current_role)
        Thread.current[FRAME_KEY] = connected_to_stack&.last
      end

      def drop_owned_frame
        stack = connected_to_stack.to_a
        stack.pop if stack.last.equal?(Thread.current[FRAME_KEY])
      end

      # Unwinding to the recorded depth is no longer enough now that one frame
      # is reused: the frame sitting at that depth may be the one this switch
      # pushed. Re-applying the recorded shard puts the identity back without
      # growing the stack, because #apply_native replaces that frame.
      def restore_shard(shard)
        return if shard.nil? || !native_capable? || base_class.current_shard == shard

        apply_native(shard)
      end

      def apply_fallback(shard)
        desired = expected_db_config_name(shard)
        return if desired && desired.to_s == current_db_config_name.to_s

        shard ? base_class.establish_connection(shard.to_sym) : base_class.establish_connection
      end

      def unwind_stack(depth)
        stack = connected_to_stack
        return if stack.nil? || depth.nil?

        stack.pop while stack.size > depth
      end

      def reestablish(name)
        return if name.nil? || name.to_s == current_db_config_name.to_s

        base_class.establish_connection(name.to_sym)
      end

      def shard_pool(shard)
        handler = base_class.try(:connection_handler)
        spec_name = base_class.try(:connection_specification_name)
        return nil if spec_name.nil? || !handler.respond_to?(:retrieve_connection_pool)

        handler.retrieve_connection_pool(spec_name, role: base_class.current_role, shard: shard.to_sym)
      end

      def expected_db_config_name(shard) = shard ? shard.to_s : config_name(env_configs.first)

      def env_configs
        configs = base_class.try(:configurations)
        env = current_db_config.try(:env_name)
        return [] if env.nil? || !configs.respond_to?(:configs_for)

        configs.configs_for(env_name: env)
      end

      # `connection_pool` raises when nothing is established yet; that is a
      # legitimate "no identity" answer, unlike a programming error.
      def current_db_config
        base_class.try(:connection_pool).try(:db_config)
      rescue StandardError => e
        raise e if self.class.programming_error?(e)

        nil
      end

      def current_db_config_name = config_name(current_db_config)

      # Rails 6.1 renamed DatabaseConfig#spec_name to #name; support both.
      def config_name(config)
        return nil if config.nil?

        config.respond_to?(:name) ? config.name : config.try(:spec_name)
      end
    end
  end
end
