# spec/console_kit/steps/tenant_selector_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Steps::TenantSelector do
  subject(:step) { described_class.new(ctx) }

  let(:config) { ConsoleKit.configuration }
  let(:ctx)    { ConsoleKit::PipelineContext.new(config: config) }

  before do
    ConsoleKit.configure do |c|
      c.tenants = { tenant_a: { constants: { shard: 's', partner_code: 'p' } } }
      c.context_class = 'Object'
    end
  end

  it 'returns success and skips when ctx.skip_selector true' do
    ctx.skip_selector = true
    expect(step.call.success?).to be true
  end

  it 'does not set resolved_tenant when skip_selector' do
    ctx.skip_selector = true
    step.call
    expect(ctx.resolved_tenant).to be_nil
  end

  it 'returns success and skips when ctx.scoped true' do
    ctx.scoped = true
    expect(step.call.success?).to be true
  end

  it 'auto-selects single tenant without prompting' do
    step.call
    expect(ctx.resolved_tenant).to eq(:tenant_a)
  end

  context 'when multiple tenants are configured' do
    let(:multi_step) { described_class.new(ctx) }

    before do
      ConsoleKit.configure do |c|
        c.tenants = {
          t1: { constants: { shard: 's', partner_code: 'p' } },
          t2: { constants: { shard: 's', partner_code: 'p' } }
        }
      end
    end

    it 'returns failure when selection is :abort' do
      allow(multi_step).to receive(:interactive_select).and_return(:abort)
      expect(multi_step.call.failure?).to be true
    end

    it 'returns failure when selection is nil' do
      allow(multi_step).to receive(:interactive_select).and_return(nil)
      expect(multi_step.call.failure?).to be true
    end

    it 'sets resolved_tenant from interactive selection' do
      allow(multi_step).to receive(:interactive_select).and_return(:t1)
      multi_step.call
      expect(ctx.resolved_tenant).to eq(:t1)
    end

    it 'uses LegacyTenantSelector when tty-prompt unavailable' do
      stub_const('TTY_PROMPT_AVAILABLE', false)
      allow(ConsoleKit::LegacyTenantSelector).to receive(:select).and_return(:t2)
      result = multi_step.call
      expect(result.success?).to be true
    end

    it 'uses PromptBuilder when tty-prompt is available' do
      stub_const('TTY_PROMPT_AVAILABLE', true)
      prompt_builder = instance_double(ConsoleKit::PromptBuilder, select: :t1)
      allow(ConsoleKit::PromptBuilder).to receive(:new).and_return(prompt_builder)
      result = multi_step.call
      expect(result.success?).to be true
    end
  end

  context 'when tenants is :dynamic' do
    let(:dynamic_step) { described_class.new(ctx) }

    before do
      ConsoleKit.configure do |c|
        c.tenants = :dynamic
        c.tenant_resolver = ->(key) { key }
        c.context_class = 'Object'
      end
    end

    it 'does not auto-select (auto_select? returns false for dynamic)' do
      allow(dynamic_step).to receive(:interactive_select).and_return(:some_tenant)
      dynamic_step.call
      expect(ctx.resolved_tenant).to eq(:some_tenant)
    end

    it 'returns nil for single_tenant_key when dynamic' do
      expect(dynamic_step.send(:single_tenant_key)).to be_nil
    end
  end
end
