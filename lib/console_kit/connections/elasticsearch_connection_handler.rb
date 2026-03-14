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

      def available? = defined?(Elasticsearch)

      private

      def apply_model_index_prefix(prefix)
        return unless defined?(Elasticsearch::Model) && Elasticsearch::Model.respond_to?(:index_name_prefix=)

        Elasticsearch::Model.index_name_prefix = prefix
      end

      def switch_message(prefix)
        prefix ? "Setting Elasticsearch index prefix: #{prefix}" : 'Resetting Elasticsearch index prefix to default'
      end
    end
  end
end
