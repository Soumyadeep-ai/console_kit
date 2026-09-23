# frozen_string_literal: true

require_relative 'errors'
require_relative 'output'
require_relative 'connections/diagnostic_helpers'

module ConsoleKit
  # One tenant as it was configured: its identifier and the entry declared under
  # it. Every per-tenant check needs both halves - the key only to name the tenant
  # it is complaining about - so the checks are this pair's own behaviour, and
  # ConfigurationValidator just collects what they found.
  class TenantEntry
    # Constants keys ConsoleKit reads without routing them through a backend
    # handler, so `context_mapping` does not know about them.
    EXTRA_CONSTANTS_KEYS = [:environment].freeze

    attr_reader :key, :errors, :warnings

    def initialize(key, entry)
      @key = key
      @entry = entry
      @errors = []
      @warnings = []
    end

    # The declared constants Hash, or nil when this tenant does not have a usable
    # one - the checks across tenants can only speak for the tenants that do.
    def constants
      constants = @entry[:constants] if @entry.is_a?(Hash)
      constants if constants.is_a?(Hash)
    end

    def validate
      check_identifier
      return @errors << "ConsoleKit: tenant #{@key.inspect} configuration must be a Hash, got #{@entry.class}." \
        unless @entry.is_a?(Hash)

      validate_constants
    end

    private

    def validate_constants
      declared = @entry[:constants]
      tenant = @key.inspect
      return @errors << "ConsoleKit: tenant #{tenant} is missing a `:constants` Hash." if declared.nil?
      unless declared.is_a?(Hash)
        return @errors << "ConsoleKit: tenant #{tenant} `:constants` must be a Hash, got #{declared.class}."
      end

      check_required_keys
      check_constants_values
      warn_unknown_keys
    end

    def check_identifier
      return if (@key.is_a?(Symbol) || @key.is_a?(String)) && @key.to_s.strip.present?

      @errors << "ConsoleKit: tenant identifier #{@key.inspect} must be a non-blank Symbol or String."
    end

    def check_required_keys
      required = TenantPlan::REQUIRED_KEYS
      missing = required - constants.keys
      return if missing.empty?

      @errors << "ConsoleKit: tenant #{@key.inspect} constants missing required keys: #{missing.join(', ')} " \
                 "(expected: #{required.join(', ')})."
    end

    # Calling each handler's own `.target_error`, rather than re-deriving the rule,
    # is what keeps this check and the handler's `#prepare` from drifting apart.
    def check_constants_values
      values = constants
      Connections::BaseConnectionHandler.registry.each do |handler_class|
        field = handler_class.constants_key
        next unless values.key?(field)

        check_backend_value(field, values[field], handler_class)
      end
    end

    def check_backend_value(field, value, handler_class)
      reason = handler_class.target_error(value)
      return unless reason

      scrubbed = Connections::DiagnosticHelpers.scrub(value.inspect)
      @errors << "ConsoleKit: tenant #{@key.inspect} #{field} #{scrubbed} is invalid: #{reason}"
    end

    def warn_unknown_keys
      recognised = TenantConfigurator.context_mapping.values + EXTRA_CONSTANTS_KEYS
      extra = constants.keys - recognised
      return if extra.empty?

      @warnings << "tenant #{@key.inspect} constants has unrecognised keys: #{extra.map(&:inspect).join(', ')} " \
                   "(recognised: #{recognised.map(&:inspect).join(', ')}). Check for typos."
    end
  end

  # An omitted backend key does not mean "leave that backend alone": a switch
  # RESETS that backend to its default, which is what stops a tenant from ending
  # up half on the tenant before it. Tenants that disagree with each other about
  # which backends they name are where that bites, so only those are reported.
  class BackendCoverage
    WARNING = 'tenant %<tenant>p does not name %<omitted>s, which other tenants do. Switching to it RESETS those ' \
              'backends to their defaults rather than leaving them on the tenant before it.'

    def initialize(entries)
      @entries = entries.select(&:constants)
    end

    def warnings
      @entries.filter_map do |entry|
        omitted = named - entry.constants.keys
        next if omitted.empty?

        format(WARNING, tenant: entry.key, omitted: omitted.map(&:inspect).join(', '))
      end
    end

    private

    def named
      @named ||= @entries.flat_map { |entry| entry.constants.keys }
                         .intersection(Connections::BaseConnectionHandler.registry.map(&:constants_key))
    end
  end

  # Deep validation of a Configuration's tenant map and context class, run by
  # Configuration#validate! once the bare presence checks pass. Errors are
  # aggregated and raised together; warnings are printed via Output, never raised.
  class ConfigurationValidator
    def initialize(configuration)
      @configuration = configuration
      @errors = []
      @warnings = []
    end

    def validate!
      entries.each do |entry|
        entry.validate
        errors.concat(entry.errors)
        warnings.concat(entry.warnings)
      end
      check_across_tenants
      raise ConfigurationError, errors.join("\n") if errors.any?
    end

    private

    attr_reader :configuration, :errors, :warnings

    def entries = @entries ||= configuration.tenants.map { |key, entry| TenantEntry.new(key, entry) }

    # The checks that need every tenant at once, plus the context class they share.
    def check_across_tenants
      check_duplicate_identifiers
      warnings.concat(BackendCoverage.new(entries).warnings)
      check_context_writers
      warnings.each { |message| Output.print_warning("ConsoleKit: #{message}") }
    end

    def check_duplicate_identifiers
      configuration.tenants.keys.group_by { |key| key.to_s.downcase }.each_value do |keys|
        next if keys.size < 2

        errors << "ConsoleKit: tenant identifiers #{keys.map(&:inspect).join(', ')} are duplicates once " \
                  'normalized (differ only by type or case). Tenant lookup uses an exact match, so only one ' \
                  'of these is ever reachable.'
      end
    end

    def check_context_writers
      klass = resolve_context_class
      missing = klass && configured_attributes.reject { |attr| writer?(klass, :"#{attr}=") }
      return if missing.blank?

      warnings << "context_class #{klass} has no writer for: #{missing.join(', ')}. ConsoleKit will silently " \
                  'never configure that backend during a tenant switch.'
    end

    # Only backends some tenant actually names can be configured, so only those
    # can be silently dropped - warning about the rest is noise about a switch
    # that was never going to happen.
    def configured_attributes
      named = entries.filter_map { |entry| entry.constants&.keys }.flatten.uniq
      TenantConfigurator.context_mapping.select { |_attr, field| named.include?(field) }.keys
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
  end
end
