# frozen_string_literal: true

require_relative 'base_connection_handler'

module ConsoleKit
  module Connections
    # Handles MongoDB connections
    class MongoConnectionHandler < BaseConnectionHandler
      CONTEXT_ATTRIBUTE = :tenant_mongo_db
      DISPLAY_NAME = 'MongoDB'

      def available? = !!defined?(Mongoid)

      # Validate/resolve only, never mutates. Raises when this Mongoid version
      # cannot support client/database overrides at all.
      def prepare(_target)
        return if Mongoid.respond_to?(:override_database)

        raise UnsupportedBackendError, "#{display_name} client override API is not available in this Mongoid version."
      end

      def snapshot
        { client: current_client_override, database: current_database_override }
      end

      def connect!(target)
        if target.nil?
          reset_overrides
        elsif named_client?(target)
          Mongoid.override_client(target)
        else
          Mongoid.override_database(target)
        end
      end

      def verify!(target)
        if target.nil?
          verify_reset!
        elsif named_client?(target)
          verify_match!(target, effective_client_name)
        else
          verify_match!(target, effective_database_name)
        end
      end

      def restore(state)
        Mongoid.override_client(state[:client]) if Mongoid.respond_to?(:override_client)
        Mongoid.override_database(state[:database])
      end

      def diagnostics(level: :basic)
        return unavailable_diagnostics unless available?

        level == :full ? full_diagnostics : basic_diagnostics
      rescue StandardError => e
        error_diagnostics(display_name, e)
      end

      private

      def basic_diagnostics
        { name: display_name, status: :connected, latency_ms: nil, details: { database: effective_database_name } }
      end

      def full_diagnostics
        db = Mongoid.default_client.database
        latency = measure_latency { db.command(ping: 1) }
        info = db.command(buildInfo: 1).first
        {
          name: display_name, status: :connected, latency_ms: latency,
          details: { database: db.name, version: info['version'] }
        }
      end

      def effective_client_name = Mongoid.default_client.name
      def effective_database_name = Mongoid.default_client.database.name

      def verify_match!(target, actual)
        return if actual.to_s == target.to_s

        raise verification_error(target, actual)
      end

      def verify_reset!
        return if current_client_override.nil? && current_database_override.nil?

        raise verification_error(nil, { client: current_client_override, database: current_database_override })
      end

      def reset_overrides
        Mongoid.override_client(nil) if Mongoid.respond_to?(:override_client)
        Mongoid.override_database(nil)
      end

      def named_client?(name)
        return false unless defined?(Mongoid::Config) && Mongoid::Config.respond_to?(:clients)

        Mongoid::Config.clients.key?(name.to_s)
      end

      def current_client_override
        return nil unless defined?(Mongoid::Threaded) && Mongoid::Threaded.respond_to?(:client_override)

        Mongoid::Threaded.client_override
      end

      def current_database_override
        return nil unless defined?(Mongoid::Threaded) && Mongoid::Threaded.respond_to?(:database_override)

        Mongoid::Threaded.database_override
      end
    end
  end
end
