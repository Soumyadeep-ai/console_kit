# spec/console_kit/prompt_builder_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::PromptBuilder do
  subject(:builder) { described_class.new(config, history) }

  let(:config) do
    ConsoleKit.configure do |c|
      c.tenants = {
        tenant_a: { constants: { shard: 's1', partner_code: 'pa' } },
        tenant_b: { constants: { shard: 's2', partner_code: 'pb' } }
      }
      c.context_class = 'Object'
    end
    ConsoleKit.configuration
  end

  let(:history) { instance_double(ConsoleKit::TenantHistory, recent: ['tenant_b']) }

  describe '#choices' do
    it 'includes all configured tenants' do
      choices = builder.send(:build_choices)
      names = choices.map { |c| c[:value] }
      expect(names).to include(:tenant_a)
    end

    it 'puts recent tenants first' do
      choices = builder.send(:build_choices)
      expect(choices.first[:value]).to eq(:tenant_b)
    end

    it 'marks recent tenants with (recent) label' do
      choices = builder.send(:build_choices)
      recent_choice = choices.find { |c| c[:value] == :tenant_b }
      expect(recent_choice[:name]).to include('(recent)')
    end

    it 'deduplicates recent and full tenant lists' do
      choices = builder.send(:build_choices)
      values = choices.map { |c| c[:value] }
      expect(values.uniq).to eq(values)
    end

    it 'returns empty array when resolver raises ConsoleKit::Error' do
      allow(config.tenant_resolver_instance).to receive(:all_keys).and_raise(ConsoleKit::Error)
      expect(builder.send(:all_tenant_choices)).to eq([])
    end
  end

  describe '#select' do
    it 'returns :abort on TTY interrupt' do
      prompt = instance_double(TTY::Prompt)
      allow(TTY::Prompt).to receive(:new).and_return(prompt)
      allow(prompt).to receive(:select).and_raise(TTY::Reader::InputInterrupt)
      expect(builder.select).to eq(:abort)
    end
  end
end
