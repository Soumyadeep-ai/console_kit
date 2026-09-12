# frozen_string_literal: true

require_relative 'errors'
require_relative 'output'
require_relative 'connections/diagnostic_helpers'

module ConsoleKit
  # An omitted backend key does not mean "leave that backend alone": a switch
  # RESETS that backend to its default, which is what stops a tenant from ending
  # up half on the tenant before it. Tenants that disagree with each other about
  # which backends they name are where that bites, so only those are reported.
  class BackendCoverage
    WARNING = 'tenant %<tenant>p does not name %<omitted>s, which other tenants do. Switching to it RESETS those ' \
              'backends to their defaults rather than leaving them on the tenant before it.'

    def initialize(tenants)
      @constants = tenants.select { |_key, entry| entry.is_a?(Hash) && entry[:constants].is_a?(Hash) }
                          .transform_values { |entry| entry[:constants] }
    end

    def warnings = @constants.filter_map { |key, constants| warning_for(key, named - constants.keys) }

    private

    def named = @named ||= @constants.values.flat_map(&:keys).uniq & backend_keys
    def backend_keys = Connections::BaseConnectionHandler.registry.map(&:constants_key)

    def warning_for(key, omitted)
      return nil if omitted.empty?

      format(WARNING, tenant: key, omitted: omitted.map(&:inspect).join(', '))
    end
  end

  # Deep validation of a Configuration's tenant map and context class, run by
  # Configuration#validate! once the bare presence checks pass. Errors are
  # aggregated and raised together; warnings are printed via Output, never raised.
  class ConfigurationValidator
    # Constants keys ConsoleKit reads without routing them through a backend
    # handler, so `context_mapping` does not know about them.
    EXTRA_CONSTANTS_KEYS = [:environment].freeze

    def initialize(configuration)
      @configuration = configuration
      @errors = []
      @warnings = []
    end

    def validate!
      configuration.tenants.each { |key, entry| validate_tenant(key, entry) }
      check_duplicate_identifiers
      check_uneven_backend_coverage
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
      warn_unknown_keys(key, 'constants', constants.keys,
                        TenantConfigurator.context_mapping.values + EXTRA_CONSTANTS_KEYS)
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

    def check_uneven_backend_coverage
      warnings.concat(BackendCoverage.new(configuration.tenants).warnings)
    end

    def check_required_keys(key, constants)
      required = TenantPlan::REQUIRED_KEYS
      missing = required - constants.keys
      return if missing.empty?

      errors << "ConsoleKit: tenant #{key.inspect} constants missing required keys: #{missing.join(', ')} " \
                "(expected: #{required.join(', ')})."
    end

    # Calling each handler's own `.target_error`, rather than re-deriving the rule,
    # is what keeps this check and the handler's `#prepare` from drifting apart.
    def check_constants_values(key, constants)
      Connections::BaseConnectionHandler.registry.each do |handler_class|
        field = handler_class.constants_key
        next unless constants.key?(field)

        check_backend_value(key, field, constants[field], handler_class)
      end
    end

    def check_backend_value(key, field, value, handler_class)
      reason = handler_class.target_error(value)
      return unless reason

      errors << "ConsoleKit: tenant #{key.inspect} #{field} #{scrub_value(value)} is invalid: #{reason}"
    end

    def warn_unknown_keys(key, subject, actual, recognised)
      extra = actual - recognised
      return if extra.empty?

      warnings << "tenant #{key.inspect} #{subject} has unrecognised keys: #{extra.map(&:inspect).join(', ')} " \
                  "(recognised: #{recognised.map(&:inspect).join(', ')}). Check for typos."
    end

    def check_context_writers
      klass = resolve_context_class
      return unless klass

      attributes = TenantConfigurator.context_mapping.keys
      missing = attributes.reject { |attr| writer?(klass, :"#{attr}=") }
      return if missing.empty?

      warnings << "context_class #{klass} has no writer for: #{missing.join(', ')}. ConsoleKit will silently " \
                  'never configure that backend during a tenant switch.'
    end

    # The context object is the class itself, and a `class << self; attr_accessor`
    # writer answers `respond_to?` but not `method_defined?`. Checking only the
    # latter warned that ConsoleKit would never configure a backend it configures.
    def writer?(klass, writer) = klass.respond_to?(writer) || klass.method_defined?(writer)

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
