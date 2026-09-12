# frozen_string_literal: true

require_relative '../errors'
require_relative '../output'
require_relative '../instrumentation'

module ConsoleKit
  module Connections
    # ConsoleKit's single frame on Rails' shard stack.
    #
    # Rails' `connected_to` pops that stack BY POSITION, not by identity, so
    # ConsoleKit's frame is replaced where it already sits - below any host
    # frame - rather than re-pushed.
    #
    # The slot is a THREAD variable, not fiber-local `Thread#[]`, because Rails
    # keeps `connected_to_stack` per thread; a fiber-local slot would disagree
    # with the very stack it describes as soon as any Fiber or Enumerator ran.
    class ShardFrame
      KEY = :console_kit_sql_connected_to_frame
      STOLEN = 'ConsoleKit: a `connected_to` block removed the shard frame ConsoleKit had committed, so shard ' \
               '%<shard>p was not live while that block was open. Re-applying it now.'
      REASSERTED = 'console_kit.sql_frame_reasserted'

      attr_reader :base_class

      def initialize(base_class) = @base_class = base_class

      # Moves the frame `connecting_to` just pushed into the slot ConsoleKit
      # already owns, keeping it to one frame.
      def apply(shard)
        base_class.connecting_to(shard: shard || base_class.default_shard, role: base_class.current_role)
        place(shard)
      end

      # A host block can destroy ConsoleKit's frame on the way out, so the frame
      # goes back here - and is reported, because the queries that ran in between
      # really did use the block's shard.
      def live_shard
        reassert if taken?
        base_class.current_shard
      end

      def applied_shard
        return nil unless on?

        owned[:shard] || base_class.default_shard
      end

      # A frame given up deliberately is forgotten, so no later read mistakes it
      # for one a host block took.
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
        return nil if entry.nil? || current.nil? || !current[entry[:index]].equal?(entry[:frame])

        entry[:index]
      end

      # One slot serves the whole thread, so a record left by another base class
      # is somebody else's business.
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

    # The base class's connection pool as a thing that can be ABSENT.
    # `connection_pool` cannot say "there is none" without raising, so absence is
    # read through the handler's own lookup wherever there is one.
    class PoolSlot
      attr_reader :base_class

      def initialize(base_class) = @base_class = base_class

      def absent? = lookup.nil?

      # A pool established where there was none is removed, not re-pointed:
      # re-pointing leaves the failed tenant's database connected.
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

    # Rails-version-tolerant plumbing for pointing a SQL base class at a shard:
    # `connecting_to` for a shard registered through `connects_to shards:`,
    # `establish_connection` for a plain database.yml configuration name.
    #
    # Every Rails API touched here is feature-detected with `respond_to?`, never
    # by Rails version, so one code path serves Rails 6.1 through 8.0.
    class SqlStrategy
      NATIVE_METHODS = %i[connecting_to connected_to_stack default_shard current_shard current_role].freeze

      class << self
        def programming_error?(error) = ConsoleKit.programming_error?(error)
      end

      attr_reader :base_class

      def initialize(base_class) = @base_class = base_class

      def switchable? = base_class.respond_to?(:establish_connection) || native_capable?

      # A nil shard means "default": the native path only matters there if
      # something has already pushed onto the stack.
      def native?(shard)
        return false unless native_capable?
        return !connected_to_stack.to_a.empty? if shard.nil?

        !shard_pool(shard).nil?
      end

      # An unreadable `configurations` is not evidence of a bad shard, so an
      # empty list resolves rather than rejects.
      def resolvable?(shard)
        return true if shard.nil? || native?(shard)

        configs = env_configs
        configs.empty? || configs.any? { |cfg| config_name(cfg).to_s == shard.to_s }
      end

      # A rollback has to put back the shard in ConsoleKit's OWN frame:
      # `current_shard` can be a host block's frame sitting above it.
      # `db_config_name` is nil both for "no pool" and for "a pool that cannot
      # name itself", so absence is recorded separately: only the first is undone
      # by removing what the switch established. A pool that names itself is
      # present by definition, so that is the only case that pays for the lookup.
      def snapshot
        name = current_db_config_name
        {
          shard: frame.applied_shard || base_class.try(:current_shard),
          role: base_class.try(:current_role),
          stack_depth: connected_to_stack&.size,
          db_config_name: name,
          pool_absent: name.nil? && pool.absent?
        }
      end

      def apply(shard) = native?(shard) ? apply_native(shard) : apply_fallback(shard)

      def restore(state)
        return if state.nil?

        unwind_stack(state[:stack_depth])
        restore_shard(state[:shard])
        state[:pool_absent] ? pool.remove : reestablish(state[:db_config_name])
      end

      # [expected, actual] identity of the live connection. Local reads, never a
      # network round trip; the one thing it may write is a frame a host block
      # removed - see #live_shard.
      def identity(shard)
        return [shard || base_class.default_shard, frame.live_shard] if native?(shard)

        [expected_db_config_name(shard), current_db_config_name]
      end

      # Network-free description of the resolved connection.
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

      def frame = @frame ||= ShardFrame.new(base_class)
      def pool = @pool ||= PoolSlot.new(base_class)
      def apply_native(shard) = frame.apply(shard)

      # Unwinding to the recorded depth is not enough when one frame is reused:
      # re-applying puts the identity back without growing the stack. The
      # comparison is against ConsoleKit's own frame, not `current_shard`, which
      # a host frame above ours can answer with the shard we want while ours
      # still holds the one being undone.
      def restore_shard(shard)
        return if shard.nil? || !native_capable? || (frame.applied_shard || base_class.current_shard) == shard

        apply_native(shard)
      end

      def apply_fallback(shard)
        desired = expected_db_config_name(shard)
        return if desired && desired.to_s == current_db_config_name.to_s

        shard ? base_class.establish_connection(shard.to_sym) : base_class.establish_connection
      end

      # The slot is cleared: a record of a frame that is gone would make the next
      # read think a host block had taken it, and put it back.
      def unwind_stack(depth)
        stack = connected_to_stack
        return if stack.nil? || depth.nil?

        stack.pop while stack.size > depth
        frame.forget_unless_on
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
