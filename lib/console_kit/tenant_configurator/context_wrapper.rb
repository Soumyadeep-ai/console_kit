# frozen_string_literal: true

module ConsoleKit
  module TenantConfigurator
    # Encapsulates context and attributes to resolve DataClump smells
    class ContextWrapper
      HANDLER_ATTRIBUTES = {
        Connections::SqlConnectionHandler => :tenant_shard,
        Connections::MongoConnectionHandler => :tenant_mongo_db,
        Connections::RedisConnectionHandler => :tenant_redis_db,
        Connections::ElasticsearchConnectionHandler => :tenant_elasticsearch_prefix
      }.freeze

      attr_reader :ctx, :attributes

      class << self
        def for_context(ctx)
          new(ctx, detect_attributes(ctx))
        end

        private

        def detect_attributes(ctx)
          methods = ctx.public_methods
          partner_attrs(methods) + handler_attrs(methods)
        end

        def partner_attrs(methods)
          methods.include?(:partner_identifier=) ? [:partner_identifier] : []
        end

        def handler_attrs(methods)
          HANDLER_ATTRIBUTES.each_with_object([]) do |(handler, attr), list|
            next unless methods.include?(:"#{attr}=")
            next unless handler_available?(handler)

            list << attr
          end
        end

        def handler_available?(handler_class)
          handler_class.new(nil).available?
        rescue NotImplementedError, StandardError
          false
        end
      end

      def initialize(ctx, attributes)
        @ctx = ctx
        @attributes = attributes
      end

      def any_set?
        attributes.any? { |attr| ctx.public_send(attr).present? }
      end

      def reset
        attributes.each { |attr| ctx.public_send("#{attr}=", nil) }
      end

      def assign(constant, mapping)
        attributes.map do |attr|
          existing = safe_read(attr)
          new_value = constant[mapping[attr]]
          ctx.public_send("#{attr}=", new_value)
          [attr, existing, new_value]
        end
      end

      private

      def safe_read(attr)
        ctx.public_send(attr)
      rescue StandardError
        nil
      end
    end
  end
end
