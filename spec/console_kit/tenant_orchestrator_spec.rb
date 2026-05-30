# spec/console_kit/tenant_orchestrator_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::TenantOrchestrator do
  before do
    ConsoleKit.configure do |c|
      c.tenants = { tenant_a: { constants: { shard: 's1', partner_code: 'pa' } } }
      c.context_class = 'Object'
    end
  end

  after { ConsoleKit::Context.reset! }

  describe '.run' do
    it 'runs SwitchPipeline and returns a result' do
      allow(ConsoleKit::SwitchPipeline).to receive(:run)
        .and_return(ConsoleKit::SwitchPipeline::Result.new(success: true, tenant: :tenant_a))
      result = described_class.run
      expect(result).to be_a(ConsoleKit::SwitchPipeline::Result)
    end
  end

  describe '.reset' do
    before do
      allow(ConsoleKit::SwitchPipeline).to receive(:run)
        .and_return(ConsoleKit::SwitchPipeline::Result.new(success: true, tenant: :tenant_a))
    end

    it 'resets the Context' do
      ConsoleKit::Context.push(:tenant_a)
      described_class.reset
      expect(ConsoleKit::Context.current.tenant).to be_nil
    end

    it 're-runs SwitchPipeline after reset' do
      described_class.reset
      expect(ConsoleKit::SwitchPipeline).to have_received(:run)
    end

    it 'restores prior tenant when pipeline fails' do
      ConsoleKit::Context.push(:tenant_a)
      ConsoleKit::Context.mark_configured!
      allow(ConsoleKit::SwitchPipeline).to receive(:run)
        .and_return(ConsoleKit::SwitchPipeline::Result.new(success: false, error: 'aborted'))
      described_class.reset
      expect(ConsoleKit::Context.current.tenant).to eq(:tenant_a)
    end

    it 'leaves context empty when pipeline fails with no prior tenant' do
      allow(ConsoleKit::SwitchPipeline).to receive(:run)
        .and_return(ConsoleKit::SwitchPipeline::Result.new(success: false, error: 'aborted'))
      described_class.reset
      expect(ConsoleKit::Context.current.tenant).to be_nil
    end

    it 'restores prior tenant but not configured when pipeline fails and prior was not configured' do
      ConsoleKit::Context.push(:tenant_a)
      # intentionally NOT calling mark_configured! — prior_configured is false
      allow(ConsoleKit::SwitchPipeline).to receive(:run)
        .and_return(ConsoleKit::SwitchPipeline::Result.new(success: false, error: 'aborted'))
      described_class.reset
      expect(ConsoleKit::Context.current.tenant).to eq(:tenant_a)
      expect(ConsoleKit::Context.current.configured?).to be false
    end
  end

  describe '.reapply' do
    it 'does nothing when context is not configured' do
      expect { described_class.reapply }.not_to raise_error
    end

    context 'when context is configured' do
      before do
        ConsoleKit::Context.push(:tenant_a)
        ConsoleKit::Context.mark_configured!
        allow(ConsoleKit::SwitchPipeline).to receive(:run)
          .and_return(ConsoleKit::SwitchPipeline::Result.new(success: true, tenant: :tenant_a))
      end

      it 'runs pipeline' do
        described_class.reapply
        expect(ConsoleKit::SwitchPipeline).to have_received(:run)
      end
    end
  end

  describe '.auto_select?' do
    it 'returns true when only one tenant is configured' do
      # single tenant configured
      allow(ConsoleKit).to receive(:tenants).and_return({ tenant_a: {} })
      expect(described_class.auto_select?).to be true
    end

    it 'returns false when stdin is not a tty and multiple tenants' do
      allow(ConsoleKit).to receive(:tenants).and_return({ tenant_a: {}, tenant_b: {} })
      allow($stdin).to receive(:tty?).and_return(false)
      expect(described_class.auto_select?).to be true
    end

    it 'handles nil tenants (safe navigation nil branch)' do
      allow(ConsoleKit).to receive(:tenants).and_return(nil)
      allow($stdin).to receive(:tty?).and_return(true)
      expect(described_class.auto_select?).to be false
    end
  end

  describe '.current_tenant' do
    it 'returns the current tenant from Context' do
      ConsoleKit::Context.push(:tenant_a)
      expect(described_class.current_tenant).to eq(:tenant_a)
    end

    it 'returns nil when no tenant set' do
      expect(described_class.current_tenant).to be_nil
    end
  end
end
