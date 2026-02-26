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
        return if tenant_shard.blank?

        Output.print_info("Establishing SQL connection to shard: #{tenant_shard} via #{base_class}")
        base_class.establish_connection(tenant_shard.to_sym)
      end

      def available? = base_class_defined?

      private

      def base_class
        sql_base_class_name.to_s.constantize
      rescue NameError
        raise Error, "ConsoleKit: sql_base_class '#{sql_base_class_name}' could not be found."
      end

      def base_class_defined?
        klass_name = sql_base_class_name
        klass_name.present? && Object.const_defined?(klass_name, false)
      end

      def sql_base_class_name
        current_config.sql_base_class
      end

      def current_config
        ConsoleKit.configuration
      end
    end
  end
end
