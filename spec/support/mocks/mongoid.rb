# frozen_string_literal: true

module Mongoid
  module Threaded
    class << self
      attr_accessor :client_override, :database_override
    end
  end

  module Config
    class << self
      attr_accessor :clients
    end
    self.clients = {}
  end

  class Database
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def command(*); end
  end

  class Client
    def initialize(name, database_name = name)
      @name = name.to_s
      @database_name = database_name.to_s
    end

    def use(database_name)
      self.class.new(@name, database_name)
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

    def default_client
      client = Client.new(Threaded.client_override || 'default')
      Threaded.database_override ? client.use(Threaded.database_override) : client
    end
  end
end

module MongoidMocks
  MONGOID = ::Mongoid

  module WithoutClientOverride
    Config = ::Mongoid::Config
    Threaded = ::Mongoid::Threaded

    class << self
      def override_database(name) = MONGOID.override_database(name)
      def default_client = MONGOID.default_client
    end
  end

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
