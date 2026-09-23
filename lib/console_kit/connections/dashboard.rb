# frozen_string_literal: true

require_relative 'table_renderer'
require_relative '../diagnostics'

module ConsoleKit
  module Connections
    module Dashboard
      class << self
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
