# frozen_string_literal: true

require_relative 'base_connection_handler'
require_relative 'mongoid_support'

module ConsoleKit
  module Connections
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

      def available? = mongoid.available?

      def prepare(target)
        validate_target!(target)
        setter = mongoid.setter_for(target)
        raise UnsupportedBackendError, unsupported_message(setter) unless mongoid.settable?(setter)
        raise UnsupportedBackendError, "#{display_name} #{UNVERIFIABLE}" unless mongoid.readable?
      end

      def snapshot = mongoid.overrides

      def connect!(target) = mongoid.override(target)

      def verify!(target)
        if target.nil?
          verify_reset!
        elsif mongoid.named_client?(target)
          verify_match!(target, mongoid.client_override)
        else
          verify_match!(target, mongoid.database_name)
        end
      end

      def restore(state) = mongoid.restore(state)

      private

      def mongoid = MongoidSupport

      def basic_diagnostics
        { name: display_name, status: :connected, latency_ms: nil, details: { database: mongoid.database_name } }
      end

      def full_diagnostics
        latency = measure_latency { mongoid.ping }
        {
          name: display_name, status: :connected, latency_ms: latency,
          details: { database: mongoid.database_name, version: mongoid.server_version }
        }
      end

      def unsupported_message(setter) = "#{display_name} #{format(UNSUPPORTED_OVERRIDE, setter: setter)}"

      def verify_match!(target, actual)
        return if actual.to_s == target.to_s

        raise verification_error(target, actual)
      end

      def verify_reset!
        overrides = mongoid.overrides
        return if overrides.values.none?

        raise verification_error(nil, overrides)
      end
    end
  end
end
