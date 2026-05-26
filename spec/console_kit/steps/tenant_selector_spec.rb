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

    it 'sets resolved_tenant from interactive selection' do
      allow(multi_step).to receive(:interactive_select).and_return(:t1)
      multi_step.call
      expect(ctx.resolved_tenant).to eq(:t1)
    end
  end
end
