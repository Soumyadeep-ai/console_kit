# frozen_string_literal: true

require_relative '../errors'
require_relative '../output'
require_relative '../instrumentation'

module ConsoleKit
  module Connections
    class ShardFrame
      KEY = :console_kit_sql_connected_to_frame
      STOLEN = 'ConsoleKit: a `connected_to` block removed the shard frame ConsoleKit had committed, so shard ' \
               '%<shard>p was not live while that block was open. Re-applying it now.'
      REASSERTED = 'console_kit.sql_frame_reasserted'

      attr_reader :base_class

      def initialize(base_class) = @base_class = base_class

      def apply(shard)
        base_class.connecting_to(shard: shard || base_class.default_shard, role: base_class.current_role)
        place(shard)
      end

      def live_shard
        reassert if taken?
        base_class.current_shard
      end

      def applied_shard
        return nil unless on?

        owned[:shard] || base_class.default_shard
      end

      def forget_unless_on
        Thread.current.thread_variable_set(KEY, nil) if owned && !on?
      end

      def on? = !index_in.nil?

      private

      def stack = base_class.try(:connected_to_stack)
      def taken? = !owned.nil? && !on?

      def reassert
        shard = owned[:shard]
        Instrumentation.increment(REASSERTED)
        Output.print_warning(format(STOLEN, shard: shard || base_class.default_shard))
        apply(shard)
      end

      def place(shard)
        current = stack
        index = index_in
        current[index] = current.pop if index
        remember(current, index || (current.size - 1), shard)
      end

      def index_in
        current = stack
        entry = owned
        return nil unless entry && current

        index = entry[:index]
        index if current[index].equal?(entry[:frame])
      end

      def owned
        entry = Thread.current.thread_variable_get(KEY)
        entry if entry && entry[:base].equal?(base_class)
      end

      def remember(current, index, shard)
        Thread.current.thread_variable_set(
          KEY, { base: base_class, frame: current[index], index: index, shard: shard }
        )
      end
    end

    class PoolSlot
      attr_reader :base_class

      def initialize(base_class) = @base_class = base_class

      def absent? = lookup.nil?

      def remove
        return if absent?
        return handler.remove_connection_pool(spec, role: role, shard: shard) if removable_handler?

        base_class.remove_connection if base_class.respond_to?(:remove_connection)
      end

      private

      def handler = base_class.try(:connection_handler)
      def spec = base_class.try(:connection_specification_name)
      def role = base_class.try(:current_role)
      def shard = base_class.try(:current_shard)
      def removable_handler? = handler.respond_to?(:remove_connection_pool) && spec

      def lookup
        return handler.retrieve_connection_pool(spec, role: role, shard: shard) if retrievable_handler?

        base_class.try(:connection_pool)
      rescue StandardError => e
        raise e if ConsoleKit.programming_error?(e)

        nil
      end

      def retrievable_handler? = handler.respond_to?(:retrieve_connection_pool) && spec
    end

    class SqlStrategy
      NATIVE_METHODS = %i[connecting_to connected_to_stack default_shard current_shard current_role].freeze

      attr_reader :base_class

      def initialize(base_class) = @base_class = base_class

      def switchable? = base_class.respond_to?(:establish_connection) || native_capable?

      def native?(shard)
        return false unless native_capable?
        return !connected_to_stack.to_a.empty? if shard.nil?

        !shard_pool(shard).nil?
      end

      def resolvable?(shard)
        return true if !shard || native?(shard)

        configs = env_configs
        configs.empty? || configs.any? { |cfg| config_name(cfg).to_s == shard.to_s }
      end

      def snapshot
        name = current_db_config_name
        {
          shard: frame.applied_shard || base_class.try(:current_shard),
          role: base_class.try(:current_role),
          stack_depth: connected_to_stack&.size,
          db_config_name: name,
          pool_absent: !name && pool.absent?
        }
      end

      def apply(shard) = native?(shard) ? apply_native(shard) : apply_fallback(shard)

      def restore(state)
        return unless state

        unwind_stack(state[:stack_depth])
        restore_shard(state[:shard])
        state[:pool_absent] ? pool.remove : reestablish(state[:db_config_name])
      end

      def identity(shard)
        return [shard || base_class.default_shard, frame.live_shard] if native?(shard)

        [expected_db_config_name(shard), current_db_config_name]
      end

      def pool_details
        describe_pool(base_class.try(:connection_pool))
      rescue StandardError => e
        raise e if ConsoleKit.programming_error?(e)

        {}
      end

      private

      def describe_pool(live_pool)
        return {} unless live_pool

        { adapter: live_pool.try(:db_config).try(:adapter), pool_size: live_pool.try(:size),
          config: current_db_config_name, shard: base_class.try(:current_shard) }.compact
      end

      def native_capable? = NATIVE_METHODS.all? { |method| base_class.respond_to?(method) }
      def connected_to_stack = base_class.try(:connected_to_stack)

      def frame = @frame ||= ShardFrame.new(base_class)
      def pool = @pool ||= PoolSlot.new(base_class)
      def apply_native(shard) = frame.apply(shard)

      def restore_shard(shard)
        return if !shard || !native_capable? || (frame.applied_shard || base_class.current_shard) == shard

        apply_native(shard)
      end

      def apply_fallback(shard)
        desired = expected_db_config_name(shard)
        return if desired && desired.to_s == current_db_config_name.to_s

        shard ? base_class.establish_connection(shard.to_sym) : base_class.establish_connection
      end

      def unwind_stack(depth)
        stack = connected_to_stack
        return unless stack && depth

        stack.pop while stack.size > depth
        frame.forget_unless_on
      end

      def reestablish(name)
        return if !name || name.to_s == current_db_config_name.to_s

        base_class.establish_connection(name.to_sym)
      end

      def shard_pool(shard)
        handler = base_class.try(:connection_handler)
        spec_name = base_class.try(:connection_specification_name)
        return nil unless spec_name && handler.respond_to?(:retrieve_connection_pool)

        handler.retrieve_connection_pool(spec_name, role: base_class.current_role, shard: shard.to_sym)
      end

      def expected_db_config_name(shard) = shard ? shard.to_s : config_name(env_configs.first)

      def env_configs
        configs = base_class.try(:configurations)
        env = current_db_config.try(:env_name)
        return [] unless env && configs.respond_to?(:configs_for)

        configs.configs_for(env_name: env)
      end

      def current_db_config
        base_class.try(:connection_pool).try(:db_config)
      rescue StandardError => e
        raise e if ConsoleKit.programming_error?(e)

        nil
      end

      def current_db_config_name = config_name(current_db_config)

      def config_name(config) = config&.name
    end
  end
end
