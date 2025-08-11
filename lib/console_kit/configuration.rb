# frozen_string_literal: true

module ConsoleKit
  # Stores configurations
  class Configuration
    attr_accessor :pretty_output, :tenants, :context_class

    def initialize
      @pretty_output = true
      @tenants = nil
      @context_class = nil
    end
  end
end
