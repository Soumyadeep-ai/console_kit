# lib/console_kit/prompt_builder.rb
# frozen_string_literal: true

require 'tty-prompt'

module ConsoleKit
  # Wraps TTY::Prompt to present a filterable tenant selection list,
  # showing recently-used tenants first.
  class PromptBuilder
    def initialize(config, history)
      @config  = config
      @history = history
    end

    def select
      prompt = TTY::Prompt.new
      prompt.select('Select tenant:', build_choices, filter: true, per_page: 10)
    rescue TTY::Reader::InputInterrupt
      :abort
    end

    private

    def build_choices
      (recent_choices + all_tenant_choices).uniq { |choice| choice[:value] }
    end

    def recent_choices
      @history.recent.map { |name| { name: "#{name} (recent)", value: name.to_sym } }
    end

    def all_tenant_choices
      @config.tenants.keys.map { |key| { name: key.to_s, value: key } }
    end
  end
end
