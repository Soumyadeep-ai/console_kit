# frozen_string_literal: true

module Apartment
  module Tenant
    class << self
      attr_accessor :current

      def switch!(schema)
        @current = schema
      end

      def reset
        @current = 'public'
      end
    end

    self.current = 'public'
  end
end
