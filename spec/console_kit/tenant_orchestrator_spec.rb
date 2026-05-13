# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::TenantOrchestrator do
  let(:config) { ConsoleKit.configuration }
  let(:tenants) do
    {
      'acme' => { constants: { partner_code: 'ACME' } },
      'globex' => { constants: { partner_code: 'GBX' } }
    }
  end

  before do
    allow(config).to receive_messages(tenants: tenants, context_class: Object, validate!: true)
    ConsoleKit::Setup.current_tenant = nil
  end

  describe '.run' do
    let(:configurator) { class_spy(ConsoleKit::TenantConfigurator) }

    before do
      stub_const('ConsoleKit::TenantConfigurator', configurator)
    end

    it 'configures a tenant when selected' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
      allow(configurator).to receive(:configuration_success).and_return(true)

      described_class.run

      expect(configurator).to have_received(:configure_tenant).with('acme')
    end

    it 'updates current_tenant when configured' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
      allow(configurator).to receive(:configuration_success).and_return(true)

      described_class.run

      expect(ConsoleKit::Setup.current_tenant).to eq('acme')
    end

    it 'does nothing if already configured' do
      ConsoleKit::Setup.current_tenant = 'acme'

      described_class.run

      expect(configurator).not_to have_received(:configure_tenant)
    end
  end

  describe '.reset' do
    before do
      ConsoleKit::Setup.current_tenant = 'acme'
      allow(ConsoleKit::TenantConfigurator).to receive(:configuration_success).and_return(true)
      allow(ConsoleKit::TenantConfigurator).to receive(:clear)
      allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant)
    end

    it 'clears the configurator when switching' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return('globex')

      described_class.reset

      expect(ConsoleKit::TenantConfigurator).to have_received(:clear)
    end

    it 'configures the new tenant when switching' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return('globex')
      allow(ConsoleKit::TenantConfigurator).to receive(:configuration_success).and_return(true)

      described_class.reset

      expect(ConsoleKit::TenantConfigurator).to have_received(:configure_tenant).with('globex')
    end

    it 'updates current_tenant to the new tenant' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return('globex')
      allow(ConsoleKit::TenantConfigurator).to receive(:configuration_success).and_return(true)

      described_class.reset

      expect(ConsoleKit::Setup.current_tenant).to eq('globex')
    end

    it 'aborts if selection returns :abort' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return(:abort)

      described_class.reset

      expect(ConsoleKit::TenantConfigurator).not_to have_received(:clear)
    end

    it 'keeps current_tenant if aborted' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return(:abort)

      described_class.reset

      expect(ConsoleKit::Setup.current_tenant).to eq('acme')
    end
  end

  describe '.reapply' do
    it 're-configures the current tenant' do
      ConsoleKit::Setup.current_tenant = 'acme'
      allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant)

      described_class.reapply

      expect(ConsoleKit::TenantConfigurator).to have_received(:configure_tenant).with('acme')
    end
  end
end
