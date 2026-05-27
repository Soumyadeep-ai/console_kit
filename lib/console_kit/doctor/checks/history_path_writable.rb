# lib/console_kit/doctor/checks/history_path_writable.rb
# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Doctor
    module Checks
      # Checks that the directory for the recent tenant history file is writable.
      class HistoryPathWritable < Base
        def call
          path = File.expand_path(config.recent_tenant_history_path)
          dir  = File.dirname(path)
          return pass("history path writable: #{path}") if File.writable?(dir)

          warn("history path not writable: #{path}")
        end
      end
    end
  end
end
