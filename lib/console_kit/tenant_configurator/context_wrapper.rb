# frozen_string_literal: true

module ConsoleKit
  module TenantConfigurator
    # Encapsulates the tenant context object and the attributes ConsoleKit owns on
    # it. All context mutation goes through here so it can be snapshotted and put
    # back verbatim when a tenant switch fails.
    class ContextWrapper
      # Recorded when a context getter raises: writing nil over a value we could not
      # read would silently destroy it, so the attribute is skipped on restore and
      # reported as a rollback failure instead.
      UNREADABLE = :'#<console_kit unreadable>'
      UNREADABLE_MESSAGE = 'Previous value of %s could not be read, so it was left as the new tenant set it.'

      attr_reader :ctx, :attributes

      class << self
        def for_context(ctx)
          new(ctx, detect_attributes(ctx))
        end

        private

        def detect_attributes(ctx)
          methods = ctx.public_methods
          partner = methods.include?(:partner_identifier=) ? [:partner_identifier] : []
          partner + handler_attrs(methods)
        end

        def handler_attrs(methods)
          Connections::BaseConnectionHandler.registry.each_with_object([]) do |handler, list|
            attr = handler.context_attribute
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

      def current_values = attributes.to_h { |attr| [attr, safe_read(attr)] }

      # Verbatim write-back for rollback, so it must not warn or transform. Every
      # attribute is attempted even when an earlier one raises.
      def restore(values)
        failures = values.filter_map { |attr, value| restore_attribute(attr, value) }
        raise_restore_failure(failures) if failures.any?

        values
      end

      def assign(constant, mapping)
        attributes.to_h { |attr| [attr, write_attribute(attr, constant[mapping[attr]])] }
      end

      private

      def restore_attribute(attr, value)
        return [attr, Error.new(format(UNREADABLE_MESSAGE, attr))] if value == UNREADABLE

        ctx.public_send(:"#{attr}=", value)
        nil
      rescue StandardError, NotImplementedError => e
        [attr, e]
      end

      def write_attribute(attr, new_value)
        existing = safe_read(attr)
        ctx.public_send(:"#{attr}=", new_value)
        warn_case_mismatch(attr, existing, new_value)
        new_value
      end

      def raise_restore_failure(failures)
        detail = failures.map { |attr, error| "#{attr} (#{error.class})" }.join(', ')
        raise Error, "Could not restore context attributes: #{detail}. " \
                     'Those attributes are still set to the tenant the switch failed to reach.'
      end

      # A tenant whose value differs from the context's only by case is almost
      # always a configuration typo, not two distinct tenants.
      def warn_case_mismatch(attr, existing, configured)
        return unless existing.is_a?(String) && configured.is_a?(String) &&
                      existing != configured && existing.casecmp(configured).zero?

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
