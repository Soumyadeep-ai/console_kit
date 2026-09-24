# frozen_string_literal: true

module ConsoleKit
  module Prompt
    module IrbLabel
      def prompt_i = Prompt.labelled(super)
      def prompt_s = Prompt.labelled(super)
      def prompt_c = Prompt.labelled(super)
    end

    class << self
      def apply
        require 'irb' unless defined?(Pry)
        IRB::Context.prepend(IrbLabel) if defined?(IRB::Context) && !IRB::Context.include?(IrbLabel)
        Pry.config.prompt = pry_prompt if defined?(Pry)
      end

      def labelled(prompt) = prompt && "#{label.gsub('%', '%%')} #{prompt}"

      def label
        tenant = StateStore.tenant_key
        tenant ? "[#{tenant}]" : '[no-tenant]'
      end

      private

      def pry_prompt
        procs = [
          proc { |obj, nest, _| "#{ConsoleKit::Prompt.label} (#{obj}):#{nest}> " },
          proc { |obj, nest, _| "#{ConsoleKit::Prompt.label} (#{obj}):#{nest}* " }
        ]
        return procs unless defined?(Pry::Prompt)

        Pry::Prompt.try(:new, 'console_kit', 'ConsoleKit tenant prompt', procs) || procs
      end
    end
  end
end
