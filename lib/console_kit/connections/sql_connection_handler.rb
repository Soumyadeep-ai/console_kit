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

        Output.print_info("Establishing SQL connection to shard: #{tenant_shard}")
        ApplicationRecord.establish_connection(tenant_shard.to_sym)
      end

      def available?
        defined?(ApplicationRecord)
      end
    end
  end
end
