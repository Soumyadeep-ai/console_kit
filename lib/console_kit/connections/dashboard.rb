# frozen_string_literal: true

require_relative 'table_renderer'

module ConsoleKit
  module Connections
    # Displays connection diagnostics as a Unicode table
    module Dashboard
      class << self
        def display
          rows = fetch_diagnostics
          return Output.print_warning('No connections available') if rows.empty?

          Output.print_header('Connection Dashboard')
          Output.print_raw(TableRenderer.render(rows))
        end

        private

        def fetch_diagnostics
          ctx = ConsoleKit.configuration.context_class
          handlers = ConnectionManager.available_handlers(ctx)
          handlers.map(&:safe_diagnostics)
        end
      end
    end
  end
end
