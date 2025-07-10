# frozen_string_literal: true

require "rails/generators"
require "rails/generators/base"

module ConsoleKit
  module Generators
    # Generates the required files
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def copy_initializer
        initializer_path = Rails.root.join("config", "initializers", "console_kit.rb")

        if File.exist?(initializer_path)
          say_status("skipped", "Initializer already exists: #{initializer_path}", :yellow)
        else
          template "console_kit.rb", "config/initializers/console_kit.rb"
          say_status("created", "Initializer generated at #{initializer_path}", :green)
        end
      end

      def inject_project_rc_files
        rc_files = [".irbrc", ".pryrc"]
        rc_files.each do |rc|
          inject_rc_file(Rails.root.join(rc).to_s)
        end
      end

      def remind_about_customization
        say "\n✅ Setup complete!", :green
        say "👉 Please update `config/initializers/console_kit.rb` to set your `tenants` and `context_class`.", :green
        say "👉 To use your project-specific .irbrc or .pryrc, start your console like this:", :blue
        say "    irb --rcfile .irbrc", :blue
        say "    pry --rcfile .pryrc", :blue
      end

      private

      def inject_rc_file(path)
        line = "require_relative 'console_kit'"

        create_empty_file_if_missing(path)
        return if File.read(path).include?(line)

        append_to_file path, <<~RUBY
          # frozen_string_literal: true

          # Added by ConsoleKit
          #{line}
        RUBY

        say_status("added", "Injected require_relative into #{path}", :green)
      end

      def create_empty_file_if_missing(path)
        return if File.exist?(path)

        File.write(path, "")
        say_status("create", path, :green)
      end
    end
  end
end
