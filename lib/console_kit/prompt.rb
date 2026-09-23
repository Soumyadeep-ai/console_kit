# frozen_string_literal: true

module ConsoleKit
  module Prompt
    IRB_MODE = :CONSOLE_KIT
    FALLBACK_IRB_PROMPT = {
      PROMPT_I: '%N(%m):%03n> ',
      PROMPT_S: '%N(%m):%03n%l ',
      PROMPT_C: '%N(%m):%03n* ',
      RETURN: "=> %s\n"
    }.freeze

    module IrbBoot
      def initialize(*args, **kwargs, &)
        ConsoleKit::Prompt.reapply_irb_prompt
        super
      end
    end

    class << self
      def apply
        apply_irb_prompt if defined?(IRB)
        apply_pry_prompt if defined?(Pry)
      end

      def reapply_irb_prompt
        install_irb_prompt if defined?(IRB) && IRB.respond_to?(:conf)
      rescue StandardError => e
        Output.print_warning("ConsoleKit could not apply the tenant prompt: #{e.class}.")
        nil
      end

      private

      def tenant_label
        tenant = ConsoleKit::StateStore.tenant_key
        tenant ? "[#{tenant}]" : '[no-tenant]'
      end

      def apply_irb_prompt
        install_irb_prompt
        hook_irb_boot
      end

      def hook_irb_boot
        return unless defined?(IRB::Irb)
        return if IRB::Irb.include?(IrbBoot)

        IRB::Irb.prepend(IrbBoot)
      end

      def install_irb_prompt
        conf = IRB.conf
        prompts = (conf[:PROMPT] ||= {})
        @irb_source = capture_source(conf, prompts)
        prompts[IRB_MODE] = decorate(@irb_source)
        conf[:PROMPT_MODE] = IRB_MODE
      end

      def capture_source(conf, prompts)
        mode = conf[:PROMPT_MODE]
        return @irb_source if mode == IRB_MODE && @irb_source

        prompts[mode] || @irb_source || FALLBACK_IRB_PROMPT
      end

      def decorate(source)
        label = tenant_label
        source.merge(
          PROMPT_I: prefixed(label, source[:PROMPT_I] || FALLBACK_IRB_PROMPT[:PROMPT_I]),
          PROMPT_S: prefixed(label, source[:PROMPT_S] || FALLBACK_IRB_PROMPT[:PROMPT_S]),
          PROMPT_C: prefixed(label, source[:PROMPT_C] || FALLBACK_IRB_PROMPT[:PROMPT_C])
        )
      end

      def prefixed(label, value) = "#{label} #{value}"

      def apply_pry_prompt
        procs = pry_prompt_procs(tenant_label)
        Pry.config.prompt = build_pry_prompt(procs)
      end

      def pry_prompt_procs(label)
        [
          proc { |obj, nest, _opts| "#{label} (#{obj}):#{nest}> " },
          proc { |obj, nest, _opts| "#{label} (#{obj}):#{nest}* " }
        ]
      end

      def build_pry_prompt(procs)
        return procs unless defined?(Pry::Prompt)

        Pry::Prompt.try(:new, 'console_kit', 'ConsoleKit tenant prompt', procs) || procs
      end
    end
  end
end
