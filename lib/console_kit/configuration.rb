# frozen_string_literal: true

module ConsoleKit
  # Stores ConsoleKit configurations such as tenant map and context behavior
  class Configuration
    attr_reader :pretty_output, :tenants, :context_class

    def initialize(tenants: nil, context_class: nil)
      @pretty_output = true
      @tenants = tenants
      @context_class = context_class
    end

    %i[pretty_output tenants context_class].each do |attr|
      define_method("#{attr}=") { |value| instance_variable_set("@#{attr}", value) }
    end
  end
end
