# frozen_string_literal: true

module ConsoleKit
  # Manages IRB/Pry prompt configuration, displaying tenant and environment information.
  class Prompt
    class << self
      def apply
        return unless defined?(IRB) || defined?(Pry)

        configure_irb_prompt(new.tenant_label) if defined?(IRB)
        configure_pry_prompt if defined?(Pry)
      end

      private

      def configure_irb_prompt(label)
        irb_conf = IRB.conf
        prompt_config = irb_conf[:PROMPT] ||= {}
        prompt_config[:CONSOLE_KIT] = build_irb_prompt_hash(label)
        irb_conf[:PROMPT_MODE] = :CONSOLE_KIT
        refresh_irb_context
      end

      def refresh_irb_context
        ctx = find_irb_context
        return unless ctx

        hash = IRB.conf[:PROMPT][:CONSOLE_KIT]
        ctx.prompt_i = hash[:PROMPT_I]
        ctx.prompt_n = hash[:PROMPT_N]
        ctx.prompt_s = hash[:PROMPT_S]
        ctx.prompt_c = hash[:PROMPT_C]
      end

      def find_irb_context
        return IRB.CurrentContext if IRB.respond_to?(:CurrentContext) && IRB.CurrentContext

        IRB.conf[:MAIN_CONTEXT]
      end

      def configure_pry_prompt
        primary   = proc { |*| "#{ConsoleKit::Prompt.new.tenant_label}> " }
        secondary = proc { |*| "#{ConsoleKit::Prompt.new.tenant_label}* " }
        if defined?(Pry::Prompt)
          Pry.config.prompt = Pry::Prompt.new('console_kit', 'ConsoleKit tenant prompt',
                                              [primary, secondary])
        else
          Pry.config.prompt = primary
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
