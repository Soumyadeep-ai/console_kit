# frozen_string_literal: true

module ConsoleKit
  # Stores ConsoleKit configurations such as tenant map and context behavior
  class Configuration
    attr_accessor :pretty_output, :tenants, :context_class

    def initialize(pretty_output: true, tenants: nil, context_class: nil)
      @pretty_output = pretty_output
      @tenants = tenants
      @context_class = context_class
    end
  end
end
