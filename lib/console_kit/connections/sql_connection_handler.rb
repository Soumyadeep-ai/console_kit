# frozen_string_literal: true

require 'forwardable'
require_relative 'base_connection_handler'

module ConsoleKit
  module Connections
    # Handles SQL connections
    class SqlConnectionHandler < BaseConnectionHandler
      extend Forwardable

      def_delegator :@context, :tenant_shard

      def connect
        shard = tenant_shard.presence&.to_sym
        Output.print_info("#{connection_message(shard)} via #{base_class}")
        shard ? base_class.establish_connection(shard) : base_class.establish_connection
      end

      def available? = sql_base_class_name.to_s.safe_constantize.present?

      private

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
