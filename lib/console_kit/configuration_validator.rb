# frozen_string_literal: true

require_relative 'errors'
require_relative 'output'
require_relative 'connections/diagnostic_helpers'

module ConsoleKit
  class TenantEntry
    EXTRA_CONSTANTS_KEYS = [:environment].freeze

    attr_reader :key, :errors, :warnings

    def initialize(key, entry)
      @key = key
      @entry = entry
      @errors = []
      @warnings = []
    end

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

    def configured_attributes
      named = entries.filter_map { |entry| entry.constants&.keys }.flatten.uniq
      TenantConfigurator.context_mapping.select { |_attr, field| named.include?(field) }.keys
    end

    def writer?(klass, writer) = klass.respond_to?(writer) || klass.method_defined?(writer)

    def resolve_context_class
      configuration.context_class
    rescue Error => e
      errors << e.message
      nil
    end
  end
end
