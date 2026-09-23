# frozen_string_literal: true

require_relative 'base_connection_handler'
require_relative 'elasticsearch_prefix_registry'

module ConsoleKit
  module Connections
    # Handles the Elasticsearch index-name prefix.
    #
    # `Elasticsearch::Model.index_name_prefix` is a single attribute on a shared
    # module, so the prefix is PROCESS-WIDE (#isolation_model is :process_global):
    # the last thread to #connect! wins for the whole process. ConsoleKit records
    # each live thread's requested prefix in ElasticsearchPrefixRegistry and
    # warns once as soon as two live threads disagree.
    class ElasticsearchConnectionHandler < BaseConnectionHandler
      backend :elasticsearch,
              display_name: 'Elasticsearch',
              context_attribute: :tenant_elasticsearch_prefix,
              constants_key: :elasticsearch_prefix,
              detail_label: 'ES Prefix'

      UNSUPPORTED = 'Elasticsearch does not expose index_name_prefix= in this version.'
      UNVERIFIABLE = 'Elasticsearch exposes no index_name_prefix reader in this version, so the process-wide prefix ' \
                     'cannot be read back and a switch could not be verified or rolled back. Give each tenant its ' \
                     'own index naming instead.'
      NOT_A_NAME = 'expected a String or Symbol'

      class << self
        def elasticsearch_available?
          return false unless defined?(Elasticsearch::Model)

          Elasticsearch::Model.method(:client)
          true
        rescue NameError
          false
        end

        # A blank prefix means "use the default". The type check must come
        # first: coercing with `#to_s` before checking accepts an Integer as
        # "5" and an Array as "[:acme]".
        def target_error(value)
          return NOT_A_NAME unless value.nil? || value.is_a?(String) || value.is_a?(Symbol)

          ElasticsearchPrefixRegistry.prefix_error(value.presence&.to_s)
        end
      end

      def available? = self.class.elasticsearch_available?
      def isolation_model = :process_global
      def thread_isolated? = false

      # A prefix ConsoleKit writes but cannot read back cannot be snapshotted,
      # so rollback would put nil where the previous prefix was. A reset writes
      # too, and is refused on the same terms; only a module with no setter at
      # all is left alone, because then nothing is written.
      def prepare(target)
        validate_target!(target)
        settable = registry.settable?
        raise UnsupportedBackendError, UNSUPPORTED if normalize(target) && !settable
        return unless settable

        raise UnsupportedBackendError, UNVERIFIABLE unless registry.readable?
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

      # Falls back to ConsoleKit's own record when the module exposes no reader.
      def effective_prefix = registry.readable? ? registry.global : registry.current

      # Any thread can move this process-wide attribute, so it is read back
      # rather than assumed.
      def diagnostic_identity = effective_prefix

      private

      def registry = ElasticsearchPrefixRegistry

      # No network call.
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

      # A failed ping means the cluster is unreachable, so cluster.health must
      # not be called anyway.
      def ping!(client)
        client.ping
      rescue StandardError => e
        raise ConnectionError.new("#{display_name} cluster unreachable: #{scrub(e.message)}",
                                  backend: display_name, operation: :diagnostics)
      end

      def apply_global(prefix)
        raise UnsupportedBackendError, UNSUPPORTED if prefix && !registry.settable?

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
