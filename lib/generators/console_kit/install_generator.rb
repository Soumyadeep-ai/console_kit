# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/base'

module ConsoleKit
  module Generators
    # Generates the required files
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      def copy_initializer
        initializer_path = Rails.root.join('config', 'initializers', 'console_kit.rb')

        if File.exist?(initializer_path)
          say_status('skipped', "Initializer already exists: #{initializer_path}", :yellow)
        else
          template 'console_kit.rb', 'config/initializers/console_kit.rb'
          say_status('created', "Initializer generated at #{initializer_path}", :green)
        end
      end

      def remind_about_customization
        say "\n✅ Setup complete!", :green
        say '📄 Modify `config/initializers/console_kit.rb`:', :green
        say '  - Set `tenants` (required)', :green
        say '  - Set `context_class` (required)', :green
      end
    end
  end
end
