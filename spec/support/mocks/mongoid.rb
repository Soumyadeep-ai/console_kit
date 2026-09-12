# frozen_string_literal: true

# Mock for Mongoid module to support testing
module Mongoid
  # Mock for Mongoid::Threaded thread-local override state
  module Threaded
    class << self
      attr_accessor :client_override, :database_override
    end
  end

  # Mock for Mongoid::Config
  module Config
    class << self
      attr_accessor :clients
    end
    self.clients = {}
  end

  # Mock for Mongoid Database
  class Database
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def command(*); end
  end

  # Mock for Mongoid Client
  class Client
    attr_reader :name

    def initialize(name, database_name = name)
      @name = name.to_s
      @database_name = database_name.to_s
    end

    def use(database_name)
      self.class.new(name, database_name)
    end

    def database
      Database.new(@database_name)
    end
  end

  class << self
    def override_client(name)
      Threaded.client_override = name
    end

    def override_database(name)
      Threaded.database_override = name
    end

    # Mirrors real Mongoid: the effective client honors the client override,
    # and the effective database on that client honors the database override.
    def default_client
      client = Client.new(Threaded.client_override || 'default')
      Threaded.database_override ? client.use(Threaded.database_override) : client
    end
  end
end

# Mongoid-compatible stand-ins that expose LESS than the current Mongoid does.
#
# MongoConnectionHandler feature-detects every one of these APIs with
# `respond_to?`/`defined?` rather than by version, so the shapes below are the
# ones those guards exist for.
module MongoidMocks
  MONGOID = ::Mongoid

  # A Mongoid from before `override_client`: its override state reads back
  # fine, but a target naming a configured client has no setter to reach, so
  # #connect! takes the client path and raises with the transaction open.
  module WithoutClientOverride
    Config = ::Mongoid::Config
    Threaded = ::Mongoid::Threaded

    class << self
      def override_database(name) = MONGOID.override_database(name)
      def default_client = MONGOID.default_client
    end
  end

  # Thread-local state whose client override can be written but never read
  # back, which is what the handler's `respond_to?(:client_override)` guard
  # exists for: a snapshot records no client, so a rollback clears one rather
  # than restoring it.
  module WriteOnlyClientOverride
    class << self
      attr_accessor :database_override
      attr_writer :client_override

      def reset!
        self.client_override = nil
        self.database_override = nil
      end
    end
  end

  # A facade offering only the public override API. `override_client` arrived
  # with the Mongoid 5 session-to-client rename, and Mongoid's internals
  # (`Mongoid::Threaded`, `Mongoid::Config`) are not part of the facade at all,
  # so ConsoleKit can apply an override here but can read none of its state
  # back. `overrides` is an inspection hook for specs, not part of the API the
  # handler talks to.
  module DatabaseOverrideOnly
    class << self
      def overrides = @overrides ||= []

      def override_database(name) = overrides << name

      def reset! = @overrides = []
    end
  end
end

RSpec.configure do |config|
  config.after do
    next unless defined?(Mongoid::Threaded)

    Mongoid::Threaded.client_override = nil
    Mongoid::Threaded.database_override = nil
    Mongoid::Config.clients = {} if defined?(Mongoid::Config)
  end

  config.after { MongoidMocks::DatabaseOverrideOnly.reset! }
  config.after { MongoidMocks::WriteOnlyClientOverride.reset! }
end
