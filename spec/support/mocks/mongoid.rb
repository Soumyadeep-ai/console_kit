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

RSpec.configure do |config|
  config.after do
    next unless defined?(Mongoid::Threaded)

    Mongoid::Threaded.client_override = nil
    Mongoid::Threaded.database_override = nil
    Mongoid::Config.clients = {} if defined?(Mongoid::Config)
  end
end
