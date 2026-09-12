# frozen_string_literal: true

require_relative '../errors'
require_relative '../output'
require_relative '../instrumentation'

module ConsoleKit
  module Connections
    # ConsoleKit's single frame on Rails' shard stack, and the bookkeeping that
    # keeps it single.
    #
    # `connecting_to` pushes onto that stack and Rails offers no matching pop,
    # so a committed switch has to leave one frame behind. Where that frame sits
    # is what keeps it honest:
    #
    #   * Rails' own `connected_to` pops the stack in an `ensure` BY POSITION,
    #     not by identity. A frame pushed while a host block is open is
    #     therefore destroyed by that block, leaving the block's shard live
    #     underneath ConsoleKit's committed tenant. So once ConsoleKit owns a
    #     frame it is REPLACED where it already sits, never re-pushed: below any
    #     host frame, where only Rails' own unwinding can reach it, and without
    #     ever growing the stack Rails walks on every query.
    #   * A host frame above ours wins `current_shard`, which is what a nested
    #     `connected_to` is supposed to do. A switch attempted inside one
    #     therefore fails verification and rolls back, instead of committing a
    #     tenant whose shard is not live.
    #
    # The slot is a THREAD variable rather than `Thread#[]`, which is
    # fiber-local: Rails keeps `connected_to_stack` per thread (6.1 and 7.0
    # through `thread_variable_get`, 7.1+ through IsolatedExecutionState at its
    # default :thread isolation), so a fiber-local slot would disagree with the
    # very stack it describes the moment any Fiber or Enumerator ran.
    class ShardFrame
      KEY = :console_kit_sql_connected_to_frame
      STOLEN = 'ConsoleKit: a `connected_to` block removed the shard frame ConsoleKit had committed, so shard ' \
               '%<shard>p was not live while that block was open. Re-applying it now.'
      REASSERTED = 'console_kit.sql_frame_reasserted'

      attr_reader :base_class

      def initialize(base_class) = @base_class = base_class

      # Points the base class at `shard`, keeping ConsoleKit to one frame: the
      # frame `connecting_to` just pushed is moved into the slot ConsoleKit
      # already owns, underneath any frame a host block pushed.
      def apply(shard)
        base_class.connecting_to(shard: shard || base_class.default_shard, role: base_class.current_role)
        place(shard)
      end

      # The shard that is really live. Rails pops by position, so a frame
      # ConsoleKit had to push while a host block was open is gone once that
      # block exits, leaving the block's own shard live under ConsoleKit's
      # tenant. Reporting that as ConsoleKit's would be the silent lie this
      # class exists to prevent, so the frame goes back - and is reported,
      # because the queries that ran in between did use the block's shard.
      def live_shard
        reassert if taken?
        base_class.current_shard
      end

      # The shard ConsoleKit's own frame carries, or nil when it owns none.
      def applied_shard
        return nil unless on?

        owned[:shard] || base_class.default_shard
      end

      # A frame ConsoleKit gave up deliberately is forgotten, so no later read
      # can mistake it for one a host block took.
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

      # One slot serves the whole thread, the way one stack does in Rails, so a
      # record describes ConsoleKit's frame only while it describes THIS base
      # class. A record left by another base class is somebody else's business.
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

    # Rails-version-tolerant plumbing for pointing a SQL base class at a shard.
    #
    # Two strategies are picked per target:
    #
    #   native   - the target is a shard registered through `connects_to shards:`,
    #              so `connecting_to` (Rails 6.1+) is used. It is per-thread -
    #              see ShardFrame - and touches no connection pool.
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

      # `shard` is what a rollback has to put back, and that is the shard in
      # ConsoleKit's OWN frame whenever it has one: `current_shard` can be a
      # host block's frame sitting above it, and restoring that would leave
      # ConsoleKit's frame pinned to the tenant the switch failed to reach.
      def snapshot
        {
          shard: frame.applied_shard || base_class.try(:current_shard),
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

      # [expected, actual] identity of the live connection. Local reads only:
      # the shard stack on the native path, the pool's db_config name on the
      # fallback path. Never a network round trip. The one thing it may write is
      # a frame a host block removed - see #live_shard.
      def identity(shard)
        return [shard || base_class.default_shard, frame.live_shard] if native?(shard)

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

      def frame = @frame ||= ShardFrame.new(base_class)
      def apply_native(shard) = frame.apply(shard)

      # Unwinding to the recorded depth is no longer enough now that one frame
      # is reused: the frame sitting at that depth may be the one this switch
      # replaced. Re-applying the recorded shard puts the identity back without
      # growing the stack, because #apply_native replaces that frame. What has
      # to match the recorded shard is ConsoleKit's own frame, not
      # `current_shard`: a host block's frame above ours can read back as the
      # shard we want while ours still holds the one we are undoing.
      def restore_shard(shard)
        return if shard.nil? || !native_capable? || (frame.applied_shard || base_class.current_shard) == shard

        apply_native(shard)
      end

      def apply_fallback(shard)
        desired = expected_db_config_name(shard)
        return if desired && desired.to_s == current_db_config_name.to_s

        shard ? base_class.establish_connection(shard.to_sym) : base_class.establish_connection
      end

      # A frame ConsoleKit pops here it gave up deliberately, so the slot is
      # cleared: leaving a record of a frame that is gone would make the next
      # read think a host block had taken it and put it back.
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
