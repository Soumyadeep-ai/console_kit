# frozen_string_literal: true

require_relative '../errors'

module ConsoleKit
  module Connections
    class RedisClientAdapter
      DIGITS = /\A\d+\z/
      MEMO_KEY = :console_kit_redis_isolation

      class << self
        def db_index(value)
          return value if value.is_a?(Integer) && !value.negative?
          return nil unless value.is_a?(String) && value.match?(DIGITS)

          value.to_i
        end

        def db_index_error(value)
          'expected a non-negative Integer or a digit String' unless value.nil? || db_index(value)
        end

        def read_db(target)
          return target.db if target.respond_to?(:db)

          config = target.config if target.respond_to?(:config)
          return config.db if config.respond_to?(:db)

          info = target.connection if target.respond_to?(:connection)
          info[:db] if info.respond_to?(:[])
        end
      end

      def client = resolve

      def selectable? = client.respond_to?(:select)
      def db_readable? = !current_db.nil?
      def isolation_model = @isolation_model ||= remembered_isolation

      def current_db
        Integer(client.then { |target| target && self.class.read_db(target) }, exception: false)
      end

      def movable_to?(db) = selectable? && ![nil, db].include?(current_db)

      def select(db)
        return unless selectable?

        client.select(db)
      end

      private

      def resolve
        return nil unless defined?(::Redis) && ::Redis.respond_to?(:current)

        ::Redis.current
      rescue StandardError => e
        raise e if ConsoleKit.programming_error?(e)

        nil
      end

      def remembered_isolation
        here = resolve
        memo = Thread.current[MEMO_KEY]
        return memo[:model] if memo && memo[:client].equal?(here)

        model = probe_isolation(here)
        Thread.current[MEMO_KEY] = { client: here, model: model } unless model == :unknown
        model
      end

      def probe_isolation(here)
        return :none unless here && resolve.equal?(here)

        elsewhere = resolve_elsewhere
        return :unknown unless elsewhere

        elsewhere.equal?(here) ? :process_global : :scoped
      end

      def resolve_elsewhere
        Thread.new { resolve }.value
      rescue StandardError => e
        raise e if ConsoleKit.programming_error?(e)

        nil
      end
    end
  end
end
