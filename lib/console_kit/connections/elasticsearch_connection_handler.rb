# frozen_string_literal: true

require_relative 'base_connection_handler'

module ConsoleKit
  module Connections
    # Handles Elasticsearch connections
    class ElasticsearchConnectionHandler < BaseConnectionHandler
      def connect
        prefix = context_attribute(:tenant_elasticsearch_prefix).presence
        Output.print_info(switch_message(prefix))
        Thread.current[:console_kit_elasticsearch_prefix] = prefix
        apply_model_index_prefix(prefix)
      end

      def available?
        !!(defined?(Elasticsearch::Model) && Elasticsearch::Model.respond_to?(:client))
      end

      def diagnostics
        name = 'Elasticsearch'
        return unavailable_diagnostics(name) unless available?

        client = Elasticsearch::Model.client
        latency = measure_latency { client.ping }
        build_elasticsearch_diagnostics(client, latency)
      rescue StandardError => exception
        error_diagnostics(name, exception)
      end

      private

      def build_elasticsearch_diagnostics(client, latency)
        {
          name: 'Elasticsearch',
          status: :connected,
          latency_ms: latency,
          details: elasticsearch_details(client.cluster.health)
        }
      end

      def elasticsearch_details(health)
        {
          prefix: context_attribute(:tenant_elasticsearch_prefix),
          cluster: health['cluster_name'],
          health: health['status']
        }
      end

      def apply_model_index_prefix(prefix)
        return unless defined?(Elasticsearch::Model)
        return unless Elasticsearch::Model.respond_to?(:index_name_prefix=)

        Elasticsearch::Model.index_name_prefix = prefix
      end

      def switch_message(prefix)
        prefix ? "Setting Elasticsearch index prefix: #{prefix}" : 'Resetting Elasticsearch index prefix to default'
      end
    end
  end
end
