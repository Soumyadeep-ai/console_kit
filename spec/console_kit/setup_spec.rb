# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Setup do
  let(:success_result) { ConsoleKit::SwitchPipeline::Result.new(success: true, tenant: :acme) }
  let(:failure_result) { ConsoleKit::SwitchPipeline::Result.new(success: false, error: 'failed') }

  before do
    ConsoleKit.configure do |config|
      config.tenants = { acme: { constants: { shard: 'shard_acme', partner_code: 'ACME' } } }
      config.context_class = 'Object'
    end
    ConsoleKit::Context.reset!
  end

  after { ConsoleKit::Context.reset! }

  describe '.current_tenant' do
    it 'reads the current tenant from Context' do
      ConsoleKit::Context.push(:acme)
      expect(described_class.current_tenant).to eq(:acme)
    end

    it 'returns nil when no tenant is set' do
      expect(described_class.current_tenant).to be_nil
    end
  end

  describe '.current_tenant=' do
    it 'pushes a tenant into Context' do
      described_class.current_tenant = :acme
      expect(ConsoleKit::Context.current.tenant).to eq(:acme)
    end

    it 'does nothing when val is nil' do
      described_class.current_tenant = nil
      expect(ConsoleKit::Context.current.tenant).to be_nil
    end
  end

  describe '.tenant_setup_successful?' do
    it 'returns false when context is unconfigured' do
      expect(described_class.tenant_setup_successful?).to be false
    end

    it 'returns true when context is configured' do
      ConsoleKit::Context.push(:acme)
      ConsoleKit::Context.mark_configured!
      expect(described_class.tenant_setup_successful?).to be true
    end
  end

  describe '.setup' do
    it 'delegates to TenantOrchestrator.run' do
      allow(ConsoleKit::TenantOrchestrator).to receive(:run).and_return(success_result)
      described_class.setup
      expect(ConsoleKit::TenantOrchestrator).to have_received(:run)
    end

    it 'returns result from TenantOrchestrator.run' do
      allow(ConsoleKit::TenantOrchestrator).to receive(:run).and_return(success_result)
      expect(described_class.setup).to eq(success_result)
    end

    it 'returns a SwitchPipeline::Result' do
      allow(ConsoleKit::SwitchPipeline).to receive(:run).and_return(success_result)
      expect(described_class.setup).to be_a(ConsoleKit::SwitchPipeline::Result)
    end
  end

  describe '.reapply' do
    it 'delegates to TenantOrchestrator.reapply' do
      allow(ConsoleKit::TenantOrchestrator).to receive(:reapply)
      described_class.reapply
      expect(ConsoleKit::TenantOrchestrator).to have_received(:reapply)
    end
  end

  describe '.reset_current_tenant' do
    it 'delegates to TenantOrchestrator.reset' do
      allow(ConsoleKit::TenantOrchestrator).to receive(:reset).and_return(failure_result)
      described_class.reset_current_tenant
      expect(ConsoleKit::TenantOrchestrator).to have_received(:reset)
    end

    it 'returns result from TenantOrchestrator.reset' do
      allow(ConsoleKit::TenantOrchestrator).to receive(:reset).and_return(failure_result)
      expect(described_class.reset_current_tenant).to eq(failure_result)
    end
  end

  describe '.auto_select?' do
    it 'delegates to TenantOrchestrator.auto_select?' do
      allow(ConsoleKit::TenantOrchestrator).to receive(:auto_select?).and_return(true)
      described_class.auto_select?
      expect(ConsoleKit::TenantOrchestrator).to have_received(:auto_select?)
    end

    it 'returns result from TenantOrchestrator.auto_select?' do
      allow(ConsoleKit::TenantOrchestrator).to receive(:auto_select?).and_return(true)
      expect(described_class.auto_select?).to be true
    end
  end
end
