# frozen_string_literal: true

require_relative 'table_renderer'
require_relative '../diagnostics'

module ConsoleKit
  module Connections
    # Displays connection diagnostics as a Unicode table
    module Dashboard
      class << self
        # Defaults to the cheap, network-free level so that displaying the
        # dashboard - including the opt-in display on tenant switch - never
        # costs a round-trip. Pass `level: :full` to ask the backends.
        def display(level: :basic)
          rows = ConsoleKit::Diagnostics.run(level: level)
          return Output.print_warning('No connections available') if rows.empty?

          Output.print_header('Connection Dashboard')
          Output.print_raw(TableRenderer.render(rows))
        end
      end
    end
  end
end
