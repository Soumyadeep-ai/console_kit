# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Steps::EnvResolver do
  subject(:step) { described_class.new(ctx) }

  let(:config) { ConsoleKit.configuration }
  let(:ctx)    { ConsoleKit::PipelineContext.new(config: config) }

  before do
    ConsoleKit.configure do |c|
      c.tenants = { tenant_a: { constants: { shard: 's1', partner_code: 'pa' } } }
      c.context_class = 'Object'
    end
  end

  after { ENV.delete('CONSOLE_KIT_TENANT') }

  it 'returns success when ENV var not set' do
    expect(step.call.success?).to be true
  end

  it 'does not set resolved_tenant when ENV not set' do
    step.call
    expect(ctx.resolved_tenant).to be_nil
  end

  it 'sets resolved_tenant from ENV var' do
    ENV['CONSOLE_KIT_TENANT'] = 'tenant_a'
    step.call
    expect(ctx.resolved_tenant).to eq(:tenant_a)
  end

  it 'sets skip_selector true when ENV matches' do
    ENV['CONSOLE_KIT_TENANT'] = 'tenant_a'
    step.call
    expect(ctx.skip_selector).to be true
  end

  it 'returns failure when ENV set but tenant not found' do
    ENV['CONSOLE_KIT_TENANT'] = 'unknown'
    expect(step.call.failure?).to be true
  end

  it 'matches tenant case-insensitively' do
    ENV['CONSOLE_KIT_TENANT'] = 'TENANT_A'
    step.call
    expect(ctx.resolved_tenant).to eq(:tenant_a)
  end

  context 'when tenants is :dynamic' do
    before do
      ConsoleKit.configure do |c|
        c.tenants = :dynamic
        c.tenant_resolver = ->(key) { key }
        c.context_class = 'Object'
      end
      ENV['CONSOLE_KIT_TENANT'] = 'any_tenant'
    end

    after { ENV.delete('CONSOLE_KIT_TENANT') }

    it 'resolves the env value directly as a symbol' do
      step.call
      expect(ctx.resolved_tenant).to eq(:any_tenant)
    end

    it 'returns success' do
      expect(step.call.success?).to be true
    end
  end
end
