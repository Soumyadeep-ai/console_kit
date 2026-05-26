# lib/console_kit/steps/tenant_configurator.rb
# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Steps
    # Pipeline step that applies tenant configuration constants to the
    # configured context class, validates required keys, wires up
    # connection handlers, and marks the context as fully configured.
    class TenantConfigurator < Base
      register priority: 50

      def call
        constants = tenant_constants
        return failure("No configuration found for tenant: #{resolved_tenant}") unless constants

        validation_error = missing_keys_error(constants)
        return validation_error if validation_error

        configure_tenant(constants)
      rescue StandardError => e
        failure("Failed to configure tenant '#{resolved_tenant}': #{e.message}")
      end

      private

      def resolved_tenant
        ctx.resolved_tenant
      end

      def tenant_constants
        config.tenants.dig(resolved_tenant, :constants)
      end

      def missing_keys_error(constants)
        missing = config.required_tenant_keys - constants.keys
        failure("Tenant constants missing keys: #{missing.join(', ')}") unless missing.empty?
      end

      def configure_tenant(constants)
        apply_context(constants)
        setup_connections
        Context.push(resolved_tenant)
        Context.mark_configured!
        Output.print_success("Tenant set to: #{resolved_tenant}")
        success
      end

      def apply_context(constants)
        ctx_class = config.context_class
        config.context_field_mapping.each do |ctx_attr, const_key|
          next unless constants.key?(const_key)

          existing = ctx_class.send(ctx_attr) if ctx_class.respond_to?(ctx_attr)
          new_val  = constants[const_key]
          warn_case_mismatch(ctx_attr, existing, new_val) if case_mismatch?(existing, new_val)
          ctx_class.send(:"#{ctx_attr}=", new_val) if ctx_class.respond_to?(:"#{ctx_attr}=")
        end
      end

      def setup_connections
        Connections::ConnectionManager.available_handlers(config.context_class).each(&:connect)
      end

      def case_mismatch?(existing, new_val)
        existing.is_a?(String) && new_val.is_a?(String) &&
          existing != new_val && existing.casecmp(new_val).zero?
      end

      def warn_case_mismatch(attr, existing, configured)
        Output.print_warning(
          "#{attr} case mismatch: context had '#{existing}', config set '#{configured}'."
        )
      end
    end
  end
end
