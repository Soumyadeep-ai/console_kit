# frozen_string_literal: true

require_relative 'base_connection_handler'

module ConsoleKit
  module Connections
    # Handles MongoDB connections
    class MongoConnectionHandler < BaseConnectionHandler
      UNSUPPORTED_OVERRIDE = 'Mongoid.%<setter>s, which this target needs, is not available in this Mongoid version.'
      UNVERIFIABLE = 'state cannot be read back in this Mongoid version, so a switch could not be verified or ' \
                     'rolled back. Give each tenant its own Mongoid client instead.'

      backend :mongo,
              display_name: 'MongoDB',
              context_attribute: :tenant_mongo_db,
              constants_key: :mongo_db,
              detail_label: 'Mongo DB'

      class << self
        def target_error(value) = identifier_error(value)
      end

      def available? = !!defined?(Mongoid)

      def prepare(target)
        validate_target!(target)
        setter = setter_for(target)
        raise UnsupportedBackendError, unsupported_message(setter) unless Mongoid.respond_to?(setter)
        raise UnsupportedBackendError, "#{display_name} #{UNVERIFIABLE}" unless readable?
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
        raise e if ConsoleKit.programming_error?(e)

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

      # #connect! sends a configured client name to override_client and every
      # other target, a reset included, to override_database, so the setter the
      # target will actually reach is the one that has to exist.
      def setter_for(target) = named_client?(target) ? :override_client : :override_database

      def unsupported_message(setter) = "#{display_name} #{format(UNSUPPORTED_OVERRIDE, setter: setter)}"

      # A switch that cannot be read back cannot be snapshotted either, so
      # #prepare refuses one rather than failing at verify with the override
      # applied and an empty snapshot that would clear it instead of restoring.
      # A rollback writes both overrides, so both have to be readable - the
      # client one only where this Mongoid can set a client override at all.
      def readable?
        return false unless Mongoid.respond_to?(:default_client) && threaded_readable?(:database_override)

        !Mongoid.respond_to?(:override_client) || threaded_readable?(:client_override)
      end

      def threaded_readable?(reader)
        defined?(Mongoid::Threaded) && Mongoid::Threaded.respond_to?(reader)
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
