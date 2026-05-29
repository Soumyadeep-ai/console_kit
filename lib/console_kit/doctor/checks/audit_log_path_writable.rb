# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Doctor
    module Checks
      # Checks audit log directory is writable when audit logging is enabled.
      class AuditLogPathWritable < Base
        def call
          return pass('audit logging disabled') unless config.audit_log

          path = File.expand_path(config.audit_log_path)
          dir  = File.dirname(path)
          return pass("audit log path writable: #{path}") if File.writable?(dir)

          warn("audit log path not writable: #{path}")
        end
      end
    end
  end
end
