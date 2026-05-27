# lib/generators/console_kit/doctor_generator.rb
# frozen_string_literal: true

require 'rails/generators'

module ConsoleKit
  module Generators
    # Rails generator that validates ConsoleKit configuration and reports issues.
    class DoctorGenerator < Rails::Generators::Base
      desc 'Validates ConsoleKit configuration and reports issues'

      class_option :verbose, type: :boolean, default: false, desc: 'Show detailed output'

      def run_checks
        require_doctor_files
        results = Doctor::CheckRunner.new(ConsoleKit.configuration).run
        Doctor::Reporter.new(results, verbose: options[:verbose]).print
        exit(1) if results.any?(&:failure?)
      end

      private

      def require_doctor_files
        Dir[File.expand_path('../../console_kit/doctor/**/*.rb', __dir__)].each do |file|
          require file
        end
      end
    end
  end
end
