# frozen_string_literal: true

# Stateful stand-ins for the Redis clients ConsoleKit talks to.
#
# Every fake models a real logical DB: `select` mutates it, and the fakes differ
# only in HOW they report that DB back, which is exactly the feature detection
# RedisClientAdapter performs. `RedisFakes::Base` therefore deliberately exposes
# no DB reader at all; subclasses add one.
module RedisFakes
  # Stands in for Redis::CannotConnectError / RedisClient::CannotConnectError.
  class CannotConnectError < StandardError; end

  # A client with a mutable logical DB, a recorded SELECT log so specs can prove
  # a code path issued no command, and a reachability switch.
  class Base
    attr_reader :selects
    attr_accessor :reachable

    def initialize(db = 0)
      @db = db
      @selects = []
      @reachable = true
    end

    # Not named `db`: only the subclasses that model a client with a public DB
    # reader are allowed to answer `#db`.
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

  # A client that reports its DB through a plain `#db` reader.
  class DbReader < Base
    def db = db_index
  end

  # A client that reports its DB through a RedisClient-style `config` object.
  class ConfigReader < Base
    # Minimal RedisClient::Config stand-in.
    Config = Struct.new(:db)

    def config = Config.new(db_index)
  end

  # A client that cannot report its DB by any route.
  class Opaque < Base; end

  # redis-rb 5.x: `Redis.current` was removed in 5.0, so there is no class-level
  # handle for ConsoleKit to reach at all.
  class V5 < DbReader; end

  # An application that hands out one client per thread, which is the only shape
  # that makes Redis DB selection genuinely tenant-isolated.
  class ThreadLocalRedis < DbReader
    def self.current = Thread.current[:redis_fake] ||= new
  end

  # A `Redis.current` that builds a brand new client on every call: nothing a
  # SELECT does could ever persist.
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

# redis-rb 4.x stand-in: `Redis.current` is a memoized, process-global singleton
# shared by every thread, and the client reports its DB only through
# `#connection`.
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
