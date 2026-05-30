# lib/console_kit/connections/shard_strategy.rb
# frozen_string_literal: true

require_relative '../output'

module ConsoleKit
  module Connections
    # Abstract base class describing the interface every shard strategy must
    # implement. Concrete strategies decide whether they are usable in the
    # current runtime and how to wrap a block of code so that database
    # operations target a specific shard.
    class ShardStrategy
      def available?
        raise NotImplementedError
      end

      def wrap(*, **, &)
        raise NotImplementedError
      end
    end

    # No-op strategy used when sharding is disabled or unavailable.
    # Reports itself as unavailable and simply yields the supplied block
    # without any connection switching. Accepts the same keyword
    # arguments as the abstract base for interface parity, but ignores
    # them because no shard switching occurs.
    class NullShardStrategy < ShardStrategy
      def available? = false

      def wrap(_shard, **_opts, &block)
        block.call
      end
    end

    # Strategy that delegates to ActiveRecord's `connected_to` API on
    # Rails 6.1 or newer. Falls back to the default connection if the
    # requested shard cannot be reached at runtime.
    class RailsConnectedToStrategy < ShardStrategy
      def available?
        return false unless defined?(ActiveRecord::Base)
        return false unless ActiveRecord::Base.respond_to?(:connected_to)
        return false unless defined?(Rails::VERSION::STRING)

        Gem::Version.new(Rails::VERSION::STRING) >= Gem::Version.new('6.1')
      end

      def wrap(shard, role: :writing, &block)
        ActiveRecord::Base.connected_to(shard: shard.to_sym, role: role, &block)
      rescue ActiveRecord::ConnectionNotEstablished => e
        Output.print_warning("Shard '#{shard}' unavailable: #{e.message}. Using default connection.")
        block.call
      end
    end
  end
end
