# frozen_string_literal: true

require_relative 'base_connection_handler'
require_relative 'sql_strategy'

module ConsoleKit
  module Connections
    # Handles SQL connections. Shard application, verification and rollback are
    # delegated to SqlStrategy, which prefers Rails' native shard switching and
    # falls back to `establish_connection` for plain database.yml names.
    class SqlConnectionHandler < BaseConnectionHandler
      backend :sql,
              display_name: 'SQL',
              context_attribute: :tenant_shard,
              constants_key: :shard,
              detail_label: 'Shard'

      DEFAULT_BASE_CLASS = 'ApplicationRecord'
      MISSING_BASE_CLASS = 'ConsoleKit: sql_base_class %<name>s could not be resolved, so SQL will NOT be switched, ' \
                           'verified or rolled back and a switch will still report itself as verified. Check the ' \
                           'class name and that the class is loaded.'

      class << self
        def target_error(value) = identifier_error(value)

        def sql_version(conn)
          conn.select_value('SELECT version()')
        rescue StandardError => e
          raise e if SqlStrategy.programming_error?(e)

          nil
        end

        def base_class_name = ConsoleKit.configuration.sql_base_class
      end

      # An unresolvable DEFAULT base class only means the application has no
      # ActiveRecord, so it stays silent; an explicitly configured one that will
      # not resolve is reported. Neither raises: raising from here would escape
      # every switch, every dashboard and the rollback's handler lookup.
      def available?
        name = self.class.base_class_name
        return true if name.to_s.safe_constantize.present?

        Output.print_warning(format(MISSING_BASE_CLASS, name: name.inspect)) unless name.to_s == DEFAULT_BASE_CLASS
        false
      end

      def prepare(target)
        validate_target!(target)
        unless strategy.switchable?
          raise UnsupportedBackendError, "#{display_name} base class #{base_class} cannot switch connections."
        end
        return if strategy.resolvable?(normalize(target))

        raise ConfigurationError,
              "ConsoleKit: SQL shard #{target.inspect} is not a registered shard or database configuration."
      end

      def snapshot = strategy.snapshot

      def connect!(target)
        shard = normalize(target)
        Output.print_info("#{connection_message(shard)} via #{base_class}")
        strategy.apply(shard)
      end

      def verify!(target)
        expected, actual = strategy.identity(normalize(target))
        return true if expected.to_s == actual.to_s

        raise verification_error(expected, actual)
      end

      def restore(state) = strategy.restore(state)

      # The `establish_connection` fallback replaces the base class's pool for
      # the whole process, so the resolved pool is what a cached diagnostic row
      # has to stay true for.
      def diagnostic_identity = strategy.pool_details

      def diagnostics(level: :basic)
        return unavailable_diagnostics unless available?

        level == :full ? full_diagnostics : basic_diagnostics
      rescue StandardError => e
        raise e if ConsoleKit.programming_error?(e)

        error_diagnostics(display_name, e)
      end

      private

      # No query.
      def basic_diagnostics
        details = strategy.pool_details
        { name: display_name, status: details.empty? ? :unknown : :connected, latency_ms: nil, details: details }
      end

      def full_diagnostics
        conn = base_class.connection
        latency = measure_latency { conn.execute('SELECT 1') }
        { name: display_name, status: :connected, latency_ms: latency, details: full_details(conn) }
      end

      def full_details(conn)
        {
          adapter: conn.adapter_name,
          pool_size: base_class.connection_pool.size,
          version: self.class.sql_version(conn).to_s.truncate(50)
        }
      end

      def strategy = @strategy ||= SqlStrategy.new(base_class)
      def normalize(target) = target.presence&.to_sym

      def base_class
        @base_class ||= begin
          name = self.class.base_class_name
          klass = name.to_s.safe_constantize
          klass || raise(ConfigurationError, "ConsoleKit: sql_base_class '#{name}' could not be found.")
        end
      end

      def connection_message(shard)
        shard ? "Establishing SQL connection to shard: #{shard}" : 'Resetting SQL connection to default'
      end
    end
  end
end
