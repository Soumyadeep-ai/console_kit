# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/base'

module ConsoleKit
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      def copy_initializer
        template 'console_kit.rb', 'config/initializers/console_kit.rb'
      end

      def remind_about_customization
        say "\n✅ Setup complete!", :green
        say '📄 Modify `config/initializers/console_kit.rb`:', :green
        %w[tenants context_class].each do |field|
          say "  - Set `#{field}` (required)", :green
        end
      end
    end
  end
end
