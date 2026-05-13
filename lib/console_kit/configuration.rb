# frozen_string_literal: true

module ConsoleKit
  # Stores ConsoleKit configurations such as tenant map and context behavior
  class Configuration
    # Value object for storing configuration settings
    Settings = Struct.new(:pretty_output, :tenants, :context_class, :sql_base_class, :show_dashboard)

    def initialize
      @settings = Settings.new(true, nil, nil, 'ApplicationRecord', false)
    end

    %i[pretty_output tenants context_class sql_base_class show_dashboard].each do |attr|
      define_method(attr) { @settings.send(attr) }
      define_method("#{attr}=") { |val| @settings.send("#{attr}=", val) }
    end

    def context_class
      val = @settings.context_class
      case val
      when String, Symbol then resolve_context_class(val)
      else val
      end
    end

    def validate
      validate!
      true
    rescue Error
      false
    end

    def validate!
      raise Error, 'ConsoleKit: `tenants` is not configured.' if tenants.blank?
      raise Error, 'ConsoleKit: `tenants` must be a Hash.' unless tenants.is_a?(Hash)
      raise Error, 'ConsoleKit: `context_class` is not configured.' if @settings.context_class.blank?
    end

    private

    def resolve_context_class(val)
      val.to_s.constantize
    rescue NameError
      raise Error, "ConsoleKit: context_class '#{val}' could not be found. " \
                   'Ensure the class is defined before configuration is accessed.'
    end
  end
end
