# frozen_string_literal: true

require_relative 'configuration_validator'

module ConsoleKit
  # Stores ConsoleKit configurations such as tenant map and context behavior
  class Configuration
    attr_accessor :pretty_output, :tenants, :sql_base_class, :show_dashboard
    attr_writer :context_class

    def initialize
      @pretty_output = true
      @context_class = nil
      @tenants = nil
      @sql_base_class = 'ApplicationRecord'
      @show_dashboard = false
    end

    def context_class
      case @context_class
      when String, Symbol then resolve_context_class(@context_class)
      else @context_class
      end
    end

    def validate!
      raise Error, 'ConsoleKit: `tenants` is not configured.' if tenants.blank?
      raise Error, 'ConsoleKit: `tenants` must be a Hash.' unless tenants.is_a?(Hash)
      raise Error, 'ConsoleKit: `context_class` is not configured.' if @context_class.blank?

      ConfigurationValidator.new(self).validate!
    end

    private

    def resolve_context_class(val)
      klass = val.to_s.safe_constantize
      return klass if klass

      raise Error, "ConsoleKit: context_class '#{val}' could not be found. " \
                   'Ensure the class is defined before configuration is accessed.'
    end
  end
end
