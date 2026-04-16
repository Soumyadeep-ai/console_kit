# frozen_string_literal: true

require_relative 'base_connection_handler'

module ConsoleKit
  module Connections
    # Handles SQL connections
    class SqlConnectionHandler < BaseConnectionHandler
      def connect
        shard = context_attribute(:tenant_shard).presence&.to_sym
        Output.print_info("#{connection_message(shard)} via #{base_class}")
        disconnect_existing_pool
        shard ? base_class.establish_connection(shard) : base_class.establish_connection
      end

      def available? = sql_base_class_name.to_s.safe_constantize.present?

      def diagnostics
        name = 'SQL'
        return unavailable_diagnostics(name) unless available?

        conn = base_class.connection
        latency = measure_latency { conn.execute('SELECT 1') }
        build_sql_diagnostics(conn, latency)
      rescue StandardError => e
        error_diagnostics(name, e)
      end

      private

      def disconnect_existing_pool
        return unless base_class.respond_to?(:connection_pool)

        pool = base_class.connection_pool
        pool&.disconnect!
      end

      def build_sql_diagnostics(conn, latency)
        {
          name: 'SQL',
          status: :connected,
          latency_ms: latency,
          details: {
            adapter: conn.adapter_name,
            pool_size: base_class.connection_pool.size,
            version: fetch_sql_version(conn).to_s.truncate(50)
          }
        }
      end

      def fetch_sql_version(conn)
        conn.select_value('SELECT version()')
      rescue StandardError
        nil
      end

      def base_class
        klass = sql_base_class_name.to_s.safe_constantize
        return klass if klass

        raise Error, "ConsoleKit: sql_base_class '#{sql_base_class_name}' could not be found."
      end

      def connection_message(shard)
        shard ? "Establishing SQL connection to shard: #{shard}" : 'Resetting SQL connection to default'
      end

      def sql_base_class_name = ConsoleKit.configuration.sql_base_class
    end
  end
end
