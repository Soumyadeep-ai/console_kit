# frozen_string_literal: true

module ConsoleKit
  module Connections
    # Everything ConsoleKit says to Mongoid's global API, in one place.
    #
    # Mongoid's override slots moved across versions - `override_client` arrived
    # after `override_database`, and `Mongoid::Threaded` only grew readers for
    # them later - so every call here is feature-detected with `respond_to?`
    # rather than by version. MongoConnectionHandler owns the switch contract
    # and the error messages; this module owns the driver, the way SqlStrategy,
    # RedisClientAdapter and ElasticsearchPrefixRegistry do for their backends.
    module MongoidSupport
      class << self
        def available? = !!defined?(Mongoid)

        def settable?(setter) = Mongoid.respond_to?(setter)

        # A switch that cannot be read back cannot be snapshotted either, so
        # #prepare refuses one rather than failing at verify with the override
        # applied and an empty snapshot that would clear it instead of restoring.
        # A rollback writes both overrides, so both have to be readable - the
        # client one only where this Mongoid can set a client override at all.
        def readable?
          return false unless Mongoid.respond_to?(:default_client) && threaded_readable?(:database_override)

          !Mongoid.respond_to?(:override_client) || threaded_readable?(:client_override)
        end

        # #override sends a configured client name to override_client and every
        # other target, a reset included, to override_database, so the setter the
        # target will actually reach is the one that has to exist.
        def setter_for(target) = named_client?(target) ? :override_client : :override_database

        def named_client?(name)
          return false unless defined?(Mongoid::Config) && Mongoid::Config.respond_to?(:clients)

          Mongoid::Config.clients.key?(name.to_s)
        end

        # Mongo::Client has no name - the client a name resolves to is anonymous -
        # so the override slot is the only readable form of "which client is in
        # force", and #prepare already refuses a Mongoid where it cannot be read.
        def client_override = threaded_readable?(:client_override) ? Mongoid::Threaded.client_override : nil

        def overrides = { client: client_override, database: database_override }

        # A reset is a restore to no overrides at all.
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
