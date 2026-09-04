# frozen_string_literal: true

require_relative 'errors'
require_relative 'output'
require_relative 'connections/diagnostic_helpers'

module ConsoleKit
  # Deep validation of a Configuration's tenant map and context class, run by
  # Configuration#validate! once the bare presence checks pass.
  #
  # Errors describe configurations that CANNOT work: every one found is
  # aggregated and raised together as a single ConfigurationError, so an
  # operator can fix everything in one pass instead of discovering problems
  # one tenant switch at a time. Warnings describe configurations that
  # probably do not do what the author intended (a typo'd constants key, a
  # context class missing a writer) and are printed via Output but never
  # raise, since they may be intentional.
  #
  # The Redis DB and Elasticsearch prefix rules are mirrored from
  # RedisConnectionHandler and ElasticsearchConnectionHandler, not
  # re-invented, so validation here and the handlers' own `#prepare` cannot
  # silently drift apart. Required tenant keys are read from
  # TenantPlan::REQUIRED_KEYS for the same reason. None of these classes are
  # `require_relative`d here: by the time `validate!` is ever called the whole
  # gem is loaded (see TenantPlan, which references TenantConfigurator the
  # same way), and requiring them here would pull the entire connections
  # stack into Configuration's load path for no benefit.
  class ConfigurationValidator
    # Pure "is this value acceptable, and if not why" rules mirrored from the
    # connection handlers' own `#prepare`, kept separate from
    # ConfigurationValidator so the two classes cannot silently drift and
    # each stays well under Metrics/ClassLength on its own.
    module FieldRules
      # Mirrors RedisConnectionHandler#normalize (private: a digit-only
      # String is accepted, anything else - including a float or a negative
      # number - is not).
      REDIS_DIGITS = /\A\d+\z/

      module_function

      def redis_db_error(value)
        return if value.nil? || (value.is_a?(Integer) && !value.negative?)
        return if value.is_a?(String) && value.match?(REDIS_DIGITS)

        'expected a non-negative Integer or a digit String (mirrors RedisConnectionHandler).'
      end

      def elasticsearch_prefix_error(value)
        prefix = value.presence&.to_s
        reason = prefix && invalid_prefix_reason(prefix)
        return unless reason

        "#{reason} (mirrors ElasticsearchConnectionHandler)."
      end

      def identifier_value_error(value)
        return if value.nil? || ((value.is_a?(String) || value.is_a?(Symbol)) && value.to_s.strip.present?)

        'expected a non-blank String or Symbol.'
      end

      # Mirrors ElasticsearchConnectionHandler#invalid_reason exactly,
      # including its check order, but reads the character classes off the
      # handler's own public constants so they cannot drift.
      def invalid_prefix_reason(prefix)
        handler = Connections::ElasticsearchConnectionHandler
        return 'must be lowercase' if prefix.match?(handler::UPPERCASE)
        return 'must not begin with _, - or +' if prefix.match?(handler::LEADING)
        return 'must not contain whitespace' if prefix.match?(handler::WHITESPACE)

        'must not contain \\ / * ? " < > | , or #' if prefix.match?(handler::ILLEGAL)
      end
    end

    def initialize(configuration)
      @configuration = configuration
      @errors = []
      @warnings = []
    end

    def validate!
      configuration.tenants.each { |key, entry| validate_tenant(key, entry) }
      check_duplicate_identifiers
      check_context_writers
      emit_warnings
      raise ConfigurationError, errors.join("\n") if errors.any?
    end

    private

    attr_reader :configuration, :errors, :warnings

    def validate_tenant(key, entry)
      check_identifier(key)
      return errors << "ConsoleKit: tenant #{key.inspect} configuration must be a Hash, got #{entry.class}." \
        unless entry.is_a?(Hash)

      warn_unknown_keys(key, 'top-level', entry.keys, [:constants])
      validate_constants(key, entry[:constants])
    end

    def validate_constants(key, constants)
      return errors << "ConsoleKit: tenant #{key.inspect} is missing a `:constants` Hash." if constants.nil?
      unless constants.is_a?(Hash)
        return errors << "ConsoleKit: tenant #{key.inspect} `:constants` must be a Hash, got #{constants.class}."
      end

      check_required_keys(key, constants)
      check_constants_values(key, constants)
      warn_unknown_keys(key, 'constants', constants.keys, TenantConfigurator::CONTEXT_MAPPING.values)
    end

    def check_identifier(key)
      return if (key.is_a?(Symbol) || key.is_a?(String)) && key.to_s.strip.present?

      errors << "ConsoleKit: tenant identifier #{key.inspect} must be a non-blank Symbol or String."
    end

    def check_duplicate_identifiers
      configuration.tenants.keys.group_by { |k| k.to_s.downcase }.each_value do |keys|
        next if keys.size < 2

        errors << "ConsoleKit: tenant identifiers #{keys.map(&:inspect).join(', ')} are duplicates once " \
                  'normalized (differ only by type or case). Tenant lookup uses an exact match, so only one ' \
                  'of these is ever reachable.'
      end
    end

    def check_required_keys(key, constants)
      required = TenantPlan::REQUIRED_KEYS
      missing = required - constants.keys
      return if missing.empty?

      errors << "ConsoleKit: tenant #{key.inspect} constants missing required keys: #{missing.join(', ')} " \
                "(expected: #{required.join(', ')})."
    end

    def check_constants_values(key, constants)
      check_redis_db(key, constants[:redis_db]) if constants.key?(:redis_db)
      check_es_prefix(key, constants[:elasticsearch_prefix]) if constants.key?(:elasticsearch_prefix)
      check_identifier_value(key, :mongo_db, constants[:mongo_db]) if constants.key?(:mongo_db)
      check_identifier_value(key, :shard, constants[:shard]) if constants.key?(:shard)
    end

    def check_redis_db(key, value)
      reason = FieldRules.redis_db_error(value)
      return unless reason

      errors << "ConsoleKit: tenant #{key.inspect} redis_db #{scrub_value(value)} is invalid: #{reason}"
    end

    def check_es_prefix(key, value)
      reason = FieldRules.elasticsearch_prefix_error(value)
      return unless reason

      errors << "ConsoleKit: tenant #{key.inspect} elasticsearch_prefix #{scrub_value(value.to_s)} is invalid: " \
                "#{reason}"
    end

    def check_identifier_value(key, field, value)
      reason = FieldRules.identifier_value_error(value)
      return unless reason

      errors << "ConsoleKit: tenant #{key.inspect} #{field} #{scrub_value(value)} is invalid: #{reason}"
    end

    # Shared by the tenant-entry (`subject: 'top-level'`) and the constants
    # (`subject: 'constants'`) unknown-key checks: both report an unexpected
    # key as a warning, not an error, since applications may carry extra
    # metadata alongside what ConsoleKit reads.
    def warn_unknown_keys(key, subject, actual, recognised)
      extra = actual - recognised
      return if extra.empty?

      warnings << "tenant #{key.inspect} #{subject} has unrecognised keys: #{extra.map(&:inspect).join(', ')} " \
                  "(recognised: #{recognised.map(&:inspect).join(', ')}). Check for typos."
    end

    def check_context_writers
      klass = resolve_context_class
      return unless klass

      attributes = [:partner_identifier] + TenantConfigurator::ContextWrapper::HANDLER_ATTRIBUTES.values
      missing = attributes.reject { |attr| klass.method_defined?(:"#{attr}=") }
      return if missing.empty?

      warnings << "context_class #{klass} has no writer for: #{missing.join(', ')}. ConsoleKit will silently " \
                  'never configure that backend during a tenant switch.'
    end

    def resolve_context_class
      configuration.context_class
    rescue Error => e
      errors << e.message
      nil
    end

    def emit_warnings
      warnings.each { |message| Output.print_warning("ConsoleKit: #{message}") }
    end

    def scrub_value(value) = Connections::DiagnosticHelpers.scrub(value.inspect)
  end
end
