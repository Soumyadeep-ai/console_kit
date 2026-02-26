# frozen_string_literal: true

require 'active_support/core_ext/string/inflections'

module ConsoleKit
  # Stores ConsoleKit configurations such as tenant map and context behavior
  class Configuration
    def initialize
      @pretty_output = true
      @tenants = nil
      @context_class = nil
      @sql_base_class = 'ApplicationRecord'
    end

    attr_accessor :pretty_output, :tenants, :sql_base_class

    attr_writer :context_class

    def context_class
      case @context_class
      when String, Symbol then resolve_context_class
      else @context_class
      end
    end

    def validate
      validate!
      true
    rescue Error
      false
    end

    def validate!
      raise Error, 'ConsoleKit: `tenants` is not configured.' if @tenants.nil? || @tenants.empty?
      raise Error, 'ConsoleKit: `context_class` is not configured.' unless @context_class
    end

    private

    def resolve_context_class
      @context_class.to_s.constantize
    rescue NameError
      raise Error, "ConsoleKit: context_class '#{@context_class}' could not be found. " \
                   'Ensure the class is defined before configuration is accessed.'
    end
  end
end
