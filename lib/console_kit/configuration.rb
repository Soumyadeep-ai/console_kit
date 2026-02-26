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

    def pretty_output = @pretty_output
    def pretty_output=(val)
      @pretty_output = val
    end

    def tenants = @tenants
    def tenants=(val)
      @tenants = val
    end

    def sql_base_class = @sql_base_class
    def sql_base_class=(val)
      @sql_base_class = val
    end

    def context_class
      case @context_class
      when String, Symbol
        @context_class.to_s.constantize
      else
        @context_class
      end
    end

    def context_class=(val)
      @context_class = val
    end

    def validate
      validate!
      true
    rescue Error
      false
    end

    def validate!
      raise Error, 'ConsoleKit: `tenants` is not configured.' if Array(@tenants).empty?
      raise Error, 'ConsoleKit: `context_class` is not configured.' unless @context_class
    end
  end
end
