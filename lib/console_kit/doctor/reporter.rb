# lib/console_kit/doctor/reporter.rb
# frozen_string_literal: true

module ConsoleKit
  module Doctor
    # Formats and prints Doctor check results to stdout.
    class Reporter
      STATUS_ICONS = { ok: '  ✓', warn: '  ⚠', error: '  ✗' }.freeze

      def initialize(results, verbose: false)
        @results = results
        @verbose = verbose
      end

      def print
        @results.each { |result| print_result(result) }
        $stdout.puts "\n#{summary}"
      end

      private

      def print_result(result)
        $stdout.puts "#{STATUS_ICONS.fetch(result.status, '  ?')}  #{result.message}"
        $stdout.puts "     #{result.check}" if @verbose
      end

      def summary
        count = @results.size
        "#{count} #{count == 1 ? 'check' : 'checks'}#{formatted_errors}#{formatted_warnings}"
      end

      def formatted_errors
        format_count(@results.count(&:failure?), 'error')
      end

      def formatted_warnings
        format_count(@results.count(&:warning?), 'warning')
      end

      def format_count(count, label)
        return '' unless count.positive?

        " (#{count} #{label}#{'s' unless count == 1})"
      end
    end
  end
end
