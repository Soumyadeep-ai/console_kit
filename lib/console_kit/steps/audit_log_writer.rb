# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Steps
    # Writes an audit log entry after a successful tenant switch.
    # No-op when config.audit_log is false.
    class AuditLogWriter < Base
      register priority: 85

      def call
        return success unless config.audit_log

        AuditLogger.new(config.audit_log_path).log(
          tenant: ctx.resolved_tenant,
          action: :tenant_switch,
          status: :success
        )
        success
      end
    end
  end
end
