# frozen_string_literal: true

module ConsoleKit
  module Connections
    module MongoidSupport
      class << self
        def available? = !!defined?(Mongoid)

        def settable?(setter) = Mongoid.respond_to?(setter)

        def readable?
          return false unless Mongoid.respond_to?(:default_client) && threaded_readable?(:database_override)

          !Mongoid.respond_to?(:override_client) || threaded_readable?(:client_override)
        end

        def setter_for(target) = named_client?(target) ? :override_client : :override_database

        def named_client?(name)
          return false unless defined?(Mongoid::Config) && Mongoid::Config.respond_to?(:clients)

          Mongoid::Config.clients.key?(name.to_s)
        end

        def client_override = threaded_readable?(:client_override) ? Mongoid::Threaded.client_override : nil

        def overrides = { client: client_override, database: database_override }

        def override(target)
          return restore({}) if target.nil?

          Mongoid.public_send(setter_for(target), target)
        end

        def restore(state)
          Mongoid.override_client(state[:client]) if Mongoid.respond_to?(:override_client)
          Mongoid.override_database(state[:database])
        end

        def database_name = database.name
        def ping = database.command(ping: 1)
        def server_version = database.command(buildInfo: 1).first['version']

        private

        def database = Mongoid.default_client.database

        def database_override = threaded_readable?(:database_override) ? Mongoid::Threaded.database_override : nil

        def threaded_readable?(reader)
          defined?(Mongoid::Threaded) && Mongoid::Threaded.respond_to?(reader)
        end
      end
    end
  end
end
