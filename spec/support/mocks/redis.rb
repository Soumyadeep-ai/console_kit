# frozen_string_literal: true

module RedisFakes
  class CannotConnectError < StandardError; end

  class Base
    attr_reader :selects
    attr_accessor :reachable

    def initialize(db = 0)
      @db = db
      @selects = []
      @reachable = true
    end

    def db_index = @db

    def select(index)
      raise CannotConnectError, 'Error connecting to Redis on rediss://app:s3cr3t@cache.internal:6379' unless reachable

      @selects << index
      @db = index
      'OK'
    end

    def ping = 'PONG'
    def info = { 'redis_version' => '7.0.0', 'used_memory_human' => '1.00M' }
  end

  class DbReader < Base
    def db = db_index
  end

  class ConfigReader < Base
    Config = Struct.new(:db)

    def config = Config.new(db_index)
  end

  class Opaque < Base; end

  class CommandOnly
    Config = Struct.new(:db)

    attr_reader :calls

    def initialize(db = 0)
      @db = db
      @calls = []
    end

    def config = Config.new(@db)
    def call(*command) = @calls << command
  end

  class V5 < DbReader; end

  class ThreadLocalRedis < DbReader
    def self.current = Thread.current[:redis_fake] ||= new
  end

  class EphemeralRedis < DbReader
    def self.current = new
  end

  class << self
    def reset!
      Thread.current[:redis_fake] = nil
      ::Redis.reset! if defined?(::Redis) && ::Redis.respond_to?(:reset!)
    end
  end
end

class Redis < RedisFakes::Base
  class << self
    attr_writer :current

    def current = @current ||= new
    def reset! = @current = nil
  end

  def connection = { host: 'cache.internal', port: 6379, db: db_index }
end

RSpec.configure do |config|
  config.after { RedisFakes.reset! }
end
