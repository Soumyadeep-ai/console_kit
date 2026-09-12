# frozen_string_literal: true

require_relative 'base_connection_handler'
require_relative 'elasticsearch_prefix_registry'

module ConsoleKit
  module Connections
    # Handles the Elasticsearch index-name prefix.
    #
    # ISOLATION MODEL: :process_global (see #isolation_model / #thread_isolated?).
    #
    # `Elasticsearch::Model.index_name_prefix` is a single attribute on a shared
    # module, and applications rely on ConsoleKit setting it, so the prefix is
    # PROCESS-WIDE. Pre-1.5 this handler also wrote a thread-local, which implied
    # a per-thread isolation the process-wide setter never delivered.
    #
    # Guaranteed:
    #   * within one thread, prepare -> snapshot -> connect! -> verify! ->
    #     restore round-trips exactly, including back to "no prefix";
    #   * #verify! reads the effective prefix back, so a foreign writer is
    #     detected before the switch is committed;
    #   * every live thread's requested prefix is recorded in
    #     ElasticsearchPrefixRegistry, and #connect! warns once (naming both
    #     prefixes) as soon as two live threads disagree.
    #
    # NOT guaranteed:
    #   * per-thread isolation. The last thread to call #connect! wins for the
    #     whole process; other threads keep reading and writing through that
    #     prefix even though the registry still shows their own. Use one tenant
    #     per process if real isolation is required.
    #
    # `Thread.current[:console_kit_elasticsearch_prefix]` is still maintained by
    # the registry as a backward-compatible read path; the registry is the
    # authority.
    class ElasticsearchConnectionHandler < BaseConnectionHandler
      backend :elasticsearch,
              display_name: 'Elasticsearch',
              context_attribute: :tenant_elasticsearch_prefix,
              constants_key: :elasticsearch_prefix,
              detail_label: 'ES Prefix'

      UNSUPPORTED = 'Elasticsearch does not expose index_name_prefix= in this version.'

      class << self
        def elasticsearch_available?
          return false unless defined?(Elasticsearch::Model)

          Elasticsearch::Model.method(:client)
          true
        rescue NameError
          false
        end

        # The one rule: a blank prefix always means "use the default", and a
        # present prefix must be a legal Elasticsearch index-name prefix. The
        # registry owns what "legal" means, since it owns the prefix itself.
        def target_error(value) = ElasticsearchPrefixRegistry.prefix_error(value.presence&.to_s)
      end

      def available? = self.class.elasticsearch_available?
      def isolation_model = :process_global
      def thread_isolated? = false

      # Validate/resolve only, never mutates.
      def prepare(target)
        validate_target!(target)
        return if normalize(target).nil?

        raise UnsupportedBackendError, UNSUPPORTED unless registry.settable?
      end

      def snapshot = { global: registry.global, thread: registry.current }

      def connect!(target)
        prefix = normalize(target)
        Output.print_info(switch_message(prefix))
        report_conflicts(prefix)
        apply_global(prefix)
        registry.record(prefix)
      end

      def verify!(target)
        expected = normalize(target)
        actual = effective_prefix
        return true if actual == expected

        raise verification_error(expected, actual)
      end

      def restore(state)
        apply_global(state[:global])
        registry.record(state[:thread])
      end

      # The prefix Elasticsearch::Model will actually use. Falls back to
      # ConsoleKit's own record when the module exposes no reader.
      def effective_prefix = registry.readable? ? registry.global : registry.current

      def diagnostics(level: :basic)
        return unavailable_diagnostics unless available?

        level == :full ? full_diagnostics : basic_diagnostics
      rescue StandardError => e
        raise e if ConsoleKit.programming_error?(e)

        error_diagnostics(display_name, e)
      end

      private

      def registry = ElasticsearchPrefixRegistry

      # Availability plus resolved identity. Performs no network call.
      def basic_diagnostics
        {
          name: display_name, status: :connected, latency_ms: nil,
          details: { prefix: effective_prefix, isolation: isolation_model }
        }
      end

      def full_diagnostics
        client = Elasticsearch::Model.client
        latency = measure_latency { ping!(client) }
        health = client.cluster.health
        {
          name: display_name, status: :connected, latency_ms: latency,
          details: { prefix: effective_prefix, cluster: health['cluster_name'], health: health['status'] }
        }
      end

      # A failed ping means the cluster is unreachable. Pre-1.5 this was swallowed
      # and cluster.health was called anyway, reporting :connected with no latency.
      def ping!(client)
        client.ping
      rescue StandardError => e
        raise ConnectionError.new("#{display_name} cluster unreachable: #{e.message}",
                                  backend: display_name, operation: :diagnostics)
      end

      def apply_global(prefix)
        raise UnsupportedBackendError, UNSUPPORTED unless registry.settable? || prefix.nil?

        registry.global = prefix
      end

      def report_conflicts(prefix)
        others = registry.unreported_conflicts(prefix)
        return if others.empty?

        Output.print_warning(
          "#{display_name} index prefix is process-global: this thread wants #{prefix.inspect} while other " \
          "live threads hold #{others.map(&:inspect).join(', ')}. The last writer wins for the whole process."
        )
      end

      def normalize(target) = target.presence&.to_s

      def switch_message(prefix)
        prefix ? "Setting Elasticsearch index prefix: #{prefix}" : 'Resetting Elasticsearch index prefix to default'
      end
    end
  end
end
