# frozen_string_literal: true

module ConsoleKit
  module TenantConfigurator
    # Encapsulates context and attributes to resolve DataClump smells
    class ContextWrapper
      attr_reader :ctx, :attributes

      def initialize(ctx, attributes)
        @ctx = ctx
        @attributes = attributes
      end

      def any_set?
        attributes.any? { |attr| ctx.public_send(attr).present? }
      end

      def reset
        attributes.each do |attr|
          ctx.public_send("#{attr}=", nil)
        end
      end

      def assign(constant, mapping)
        attributes.each do |attr|
          ctx.public_send("#{attr}=", constant[mapping[attr]])
        end
      end
    end
  end
end
