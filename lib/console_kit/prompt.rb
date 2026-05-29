# frozen_string_literal: true

module ConsoleKit
  # Manages IRB/Pry prompt configuration, displaying tenant and environment information.
  class Prompt
    class << self
      def apply
        return unless defined?(IRB) || defined?(Pry)

        label = new.tenant_label
        configure_irb_prompt(label) if defined?(IRB)
        configure_pry_prompt(label) if defined?(Pry)
      end

      private

      def configure_irb_prompt(label)
        irb_conf = IRB.conf
        prompt_config = irb_conf[:PROMPT] ||= {}
        prompt_config[:CONSOLE_KIT] = build_irb_prompt_hash(label)
        irb_conf[:PROMPT_MODE] = :CONSOLE_KIT
      end

      def configure_pry_prompt(label)
        Pry.config.prompt = proc do |_target_self, _nest_level, _pry|
          "#{label}> "
        end
      end

      def build_irb_prompt_hash(label)
        {
          PROMPT_I: "#{label} >> ",
          PROMPT_N: "#{label} .. ",
          PROMPT_S: "#{label} %l> ",
          PROMPT_C: "#{label} ?> ",
          RETURN: "=> %s\n"
        }
      end
    end

    def tenant_label
      raw_tenant = Context.current.tenant
      env        = Output.sanitize_display(rails_or_env_var)
      return '[no-tenant]' unless raw_tenant

      tenant = Output.sanitize_display(raw_tenant.to_s)
      "[#{tenant}][#{env}]"
    end

    private

    def rails_or_env_var
      return Rails.env.to_s if defined?(Rails) && Rails.respond_to?(:env)

      ENV['RAILS_ENV'] || 'unknown'
    end
  end
end
