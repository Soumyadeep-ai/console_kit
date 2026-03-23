# frozen_string_literal: true

module ConsoleKit
  # Sets the console prompt to show the current tenant
  module Prompt
    class << self
      def apply
        apply_irb_prompt if defined?(IRB)
        apply_pry_prompt if defined?(Pry)
      end

      private

      def tenant_label
        tenant = ConsoleKit::Setup.current_tenant
        tenant ? "[#{tenant}]" : '[no-tenant]'
      end

      def apply_irb_prompt
        conf = IRB.conf
        conf[:PROMPT] ||= {}
        conf[:PROMPT][:CONSOLE_KIT] = {
          PROMPT_I: "#{tenant_label} %N(%m):%03n> ",
          PROMPT_S: "#{tenant_label} %N(%m):%03n%l ",
          PROMPT_C: "#{tenant_label} %N(%m):%03n* ",
          RETURN: "=> %s\n"
        }
        conf[:PROMPT_MODE] = :CONSOLE_KIT
      end

      def apply_pry_prompt
        main_proc = proc { |obj, nest_level, _pry_instance| "#{Prompt.send(:tenant_label)} (#{obj}):#{nest_level}> " }
        wait_proc = proc { |obj, nest_level, _pry_instance| "#{Prompt.send(:tenant_label)} (#{obj}):#{nest_level}* " }

        Pry.config.prompt = build_pry_prompt(main_proc, wait_proc)
      end

      def build_pry_prompt(main_proc, wait_proc)
        if defined?(Pry::Prompt) && Pry::Prompt.respond_to?(:new)
          Pry::Prompt.new('console_kit', 'ConsoleKit tenant prompt', [main_proc, wait_proc])
        else
          [main_proc, wait_proc]
        end
      end
    end
  end
end
