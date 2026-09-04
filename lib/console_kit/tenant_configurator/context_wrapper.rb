# frozen_string_literal: true

module ConsoleKit
  module TenantConfigurator
    # Encapsulates the tenant context object and the attributes ConsoleKit owns on it.
    #
    # All context mutation goes through here so it can be snapshotted and put back
    # verbatim when a tenant switch fails.
    class ContextWrapper
      HANDLER_ATTRIBUTES = {
        Connections::SqlConnectionHandler => :tenant_shard,
        Connections::MongoConnectionHandler => :tenant_mongo_db,
        Connections::RedisConnectionHandler => :tenant_redis_db,
        Connections::ElasticsearchConnectionHandler => :tenant_elasticsearch_prefix
      }.freeze

      # Recorded by #current_values when a context getter raises. Writing nil over
      # a value we could not read would silently destroy it, and reporting the
      # rollback as successful would be a lie - so the attribute is skipped on
      # restore and reported as a rollback failure instead.
      UNREADABLE = :'#<console_kit unreadable>'

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

      # Snapshot of every ConsoleKit-owned context attribute.
      def current_values = attributes.to_h { |attr| [attr, safe_read(attr)] }

      def reset
        restore(attributes.to_h { |attr| [attr, nil] })
      end

      # Write values back verbatim. Used for rollback, so it must not warn or
      # transform anything. Every attribute is attempted even when an earlier one
      # raises, so one broken writer cannot strand the rest of the context on the
      # tenant the switch failed to reach.
      def restore(values)
        unreadable, writable = values.partition { |_attr, value| value == UNREADABLE }
        failures = write_back(writable) + unreadable.map { |attr, _| [attr, unreadable_error(attr)] }
        raise_restore_failure(failures) if failures.any?

        values
      end

      # Apply tenant constants, warning about values that differ from the
      # existing context value only by case.
      def assign(constant, mapping)
        attributes.to_h do |attr|
          existing = safe_read(attr)
          new_value = constant[mapping[attr]]
          ctx.public_send(:"#{attr}=", new_value)
          warn_case_mismatch(attr, existing, new_value) if case_mismatch?(existing, new_value)
          [attr, new_value]
        end
      end

      private

      def write_back(pairs)
        pairs.filter_map do |attr, value|
          ctx.public_send(:"#{attr}=", value)
          nil
        rescue StandardError, NotImplementedError => e
          [attr, e]
        end
      end

      def unreadable_error(attr)
        Error.new("Previous value of #{attr} could not be read, so it was left as the new tenant set it.")
      end

      def raise_restore_failure(failures)
        detail = failures.map { |attr, error| "#{attr} (#{error.class})" }.join(', ')
        raise Error, "Could not restore context attributes: #{detail}. " \
                     'Those attributes are still set to the tenant the switch failed to reach.'
      end

      def case_mismatch?(existing, new_value)
        existing.is_a?(String) && new_value.is_a?(String) &&
          existing != new_value && existing.casecmp(new_value).zero?
      end

      def warn_case_mismatch(attr, existing, configured)
        Output.print_warning(
          "#{attr} case mismatch: context had '#{existing}', config set '#{configured}'. " \
          'Check your ConsoleKit tenant configuration.'
        )
      end

      def safe_read(attr)
        ctx.public_send(attr)
      rescue StandardError, NotImplementedError => e
        Output.print_warning(
          "Could not read context attribute #{attr}: #{e.class}. Rollback will not be able to restore it."
        )
        UNREADABLE
      end
    end
  end
end
