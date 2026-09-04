# frozen_string_literal: true

# Mock for ApplicationRecord to support testing
class ApplicationRecord
  def self.establish_connection(*); end
  def self.connection; end
  def self.connection_pool; end
end

# Stand-ins for the ActiveRecord APIs the SQL connection handler actually talks
# to. Only those APIs are modelled, and they are modelled the way Rails 6.1-8.0
# behaves: `connecting_to` pushes onto a fiber-local stack, `establish_connection`
# replaces (and disconnects) the pool registered for the current owner/role/shard,
# and pools expose a `db_config` carrying `env_name`, `name` and `adapter`.
module ActiveRecordMock
  # Raised when no pool is registered for the current owner/role/shard.
  class ConnectionNotEstablished < StandardError; end

  # Raised when a name cannot be found in `configurations`.
  class AdapterNotSpecified < StandardError; end

  DbConfig = Struct.new(:env_name, :name, :adapter, keyword_init: true)

  # Adapter connection stand-in. Records every statement it is asked to run so
  # specs can prove that a code path performed no query.
  class Connection
    attr_reader :adapter_name, :statements

    def initialize(adapter_name: 'PostgreSQL', version: 'PostgreSQL 16.1 on aarch64')
      @adapter_name = adapter_name
      @version = version
      @statements = []
    end

    def execute(sql) = @statements << sql

    def select_value(sql)
      @statements << sql
      @version
    end
  end

  # Connection pool bound to a single database configuration.
  class Pool
    attr_reader :db_config, :size, :disconnects

    def initialize(db_config, size: 5)
      @db_config = db_config
      @size = size
      @disconnects = 0
    end

    def disconnect! = @disconnects += 1
  end

  # `database.yml` stand-in supporting the `configs_for(env_name:)` lookup.
  class Configurations
    def initialize(configs) = @configs = configs
    def configs_for(env_name:) = @configs.select { |config| config.env_name == env_name }
  end

  # Pools keyed by [owner, role, shard], exactly as ActiveRecord keys them.
  class ConnectionHandler
    attr_reader :disconnects

    def initialize
      @pools = {}
      @disconnects = 0
    end

    def retrieve_connection_pool(owner, role:, shard:) = @pools[[owner, role, shard]]

    def register(owner, db_config, role:, shard:) = @pools[[owner, role, shard]] = Pool.new(db_config)

    # Mirrors ActiveRecord: the replaced pool is removed and disconnected.
    def establish_connection(owner, db_config, role:, shard:)
      existing = @pools[[owner, role, shard]]
      if existing
        existing.disconnect!
        @disconnects += 1
      end
      register(owner, db_config, role: role, shard: shard)
    end
  end

  # Shard-aware base class, mirroring Rails 6.1+ `ActiveRecord::Base`.
  class Base
    class << self
      attr_accessor :configurations, :connection_handler, :connection_specification_name, :env_name

      def default_shard = :default
      def default_role = :writing
      def connected_to_stack = @connected_to_stack ||= []

      def connecting_to(role: default_role, shard: default_shard, prevent_writes: false)
        connected_to_stack << { role: role, shard: shard, prevent_writes: prevent_writes, klasses: [self] }
      end

      def current_shard = connected_to_stack.reverse_each.find { |entry| entry[:shard] }&.fetch(:shard) || default_shard
      def current_role = connected_to_stack.reverse_each.find { |entry| entry[:role] }&.fetch(:role) || default_role

      def connection_pool
        pool = connection_handler.retrieve_connection_pool(
          connection_specification_name, role: current_role, shard: current_shard
        )
        pool || raise(ConnectionNotEstablished, 'No connection pool for the current role/shard')
      end

      def establish_connection(config_name = nil)
        connection_handler.establish_connection(connection_specification_name, resolve_config(config_name),
                                                role: current_role, shard: current_shard)
      end

      def connection = @connection ||= Connection.new

      def resolve_config(config_name)
        env_configs = configurations.configs_for(env_name: env_name)
        name = (config_name || env_configs.first&.name).to_s
        env_configs.find { |config| config.name == name } ||
          raise(AdapterNotSpecified, "No database configuration named #{name}")
      end
    end
  end

  # A base class exposing none of Rails' shard APIs, so only the
  # `establish_connection` fallback is possible.
  class PlainBase
    class << self
      attr_accessor :configurations, :env_name
      attr_reader :connection_pool

      def establish_connection(config_name = nil)
        @connection_pool&.disconnect!
        @connection_pool = Pool.new(resolve_config(config_name))
      end

      def connection = @connection ||= Connection.new

      def resolve_config(config_name)
        env_configs = configurations.configs_for(env_name: env_name)
        name = (config_name || env_configs.first&.name).to_s
        env_configs.find { |config| config.name == name } ||
          raise(AdapterNotSpecified, "No database configuration named #{name}")
      end
    end
  end

  class << self
    # Builds a fresh, fully isolated shard-aware base class.
    #   configs: db_config names present in database.yml for `env`
    #   shards:  subset of those names also registered via `connects_to shards:`
    def sharded_base(configs:, shards: [], env: 'test', owner: 'ApplicationRecord')
      klass = Class.new(Base)
      prepare(klass, configs, env, owner)
      register_pool(klass, configs.first, :default)
      shards.each { |name| register_pool(klass, name, name.to_sym) }
      klass
    end

    # Builds a fresh base class without any native shard API.
    def plain_base(configs:, env: 'test')
      klass = Class.new(PlainBase)
      klass.env_name = env
      klass.configurations = configurations(configs, env)
      klass.establish_connection
      klass
    end

    def configurations(names, env) = Configurations.new(names.map { |name| db_config(env, name) })
    def db_config(env, name) = DbConfig.new(env_name: env, name: name.to_s, adapter: 'postgresql')

    private

    def prepare(klass, configs, env, owner)
      klass.env_name = env
      klass.configurations = configurations(configs, env)
      klass.connection_handler = ConnectionHandler.new
      klass.connection_specification_name = owner
    end

    def register_pool(klass, config_name, shard)
      klass.connection_handler.register(klass.connection_specification_name, config_for(klass, config_name),
                                        role: :writing, shard: shard)
    end

    def config_for(klass, name)
      klass.configurations.configs_for(env_name: klass.env_name).find { |config| config.name == name.to_s }
    end
  end
end
