# lib/console_kit/doctor/checks/adapter_supported.rb
# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Doctor
    module Checks
      # Checks that the database adapter is supported by ConsoleKit.
      class AdapterSupported < Base
        SUPPORTED = %w[mysql2 postgresql sqlite3 trilogy].freeze

        def call
          return pass('ActiveRecord not loaded') unless defined?(ActiveRecord::Base)

          adapter = detected_adapter
          return pass('could not detect adapter') unless adapter
          return pass("adapter '#{adapter}' supported") if SUPPORTED.include?(adapter)

          warn("adapter '#{adapter}' untested with ConsoleKit")
        end

        private

        def detected_adapter
          ActiveRecord::Base.connection_db_config.adapter
        rescue StandardError
          nil
        end
      end
    end
  end
end
