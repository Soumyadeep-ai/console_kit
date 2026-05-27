# frozen_string_literal: true

require_relative 'base_connection_handler'

module ConsoleKit
  module Connections
    # Handles Elasticsearch connections
    class ElasticsearchConnectionHandler < BaseConnectionHandler
      class << self
        def elasticsearch_available?
          return false unless defined?(Elasticsearch::Model)

          Elasticsearch::Model.method(:client)
          true
        rescue NameError
          false
        end

        def apply_prefix(prefix)
          return unless defined?(Elasticsearch::Model)

          Elasticsearch::Model.try(:index_name_prefix=, prefix)
        end
      end

      def connect
        prefix = context_attribute(:tenant_elasticsearch_prefix).presence
        Output.print_info(switch_message(prefix))
        Thread.current[:console_kit_elasticsearch_prefix] = prefix
        self.class.apply_prefix(prefix)
      end

      def available? = self.class.elasticsearch_available?

      def diagnostics
        return unavailable_diagnostics('Elasticsearch') unless available?

        perform_diagnostics
      rescue StandardError => e
        error_diagnostics('Elasticsearch', e)
      end

      private

      def perform_diagnostics
        client = Elasticsearch::Model.client
        latency = measure_latency do
          client.ping
        rescue StandardError
          nil
        end
        health = client.cluster.health
        build_elasticsearch_diagnostics(health['cluster_name'], health['status'], latency)
      end

      def build_elasticsearch_diagnostics(cluster, status, latency)
        {
          name: 'Elasticsearch',
          status: :connected,
          latency_ms: latency,
          details: {
            prefix: context_attribute(:tenant_elasticsearch_prefix),
            cluster: cluster,
            health: status
          }
        }
      end

      def switch_message(prefix)
        prefix ? "Setting Elasticsearch index prefix: #{prefix}" : 'Resetting Elasticsearch index prefix to default'
      end
    end
  end
end
