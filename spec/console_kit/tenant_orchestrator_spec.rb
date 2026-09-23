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
    described_class.current_tenant = nil
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

      expect(described_class.current_tenant).to eq('acme')
    end

    it 'does nothing if already configured' do
      described_class.current_tenant = 'acme'

      described_class.run

      expect(configurator).not_to have_received(:configure_tenant)
    end
  end

  describe '.reset' do
    before do
      described_class.current_tenant = 'acme'
      allow(ConsoleKit::TenantConfigurator).to receive(:configuration_success).and_return(true)
      allow(ConsoleKit::TenantConfigurator).to receive(:clear)
      allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant)
      allow(described_class).to receive(:auto_select?).and_return(false)
      allow(ConsoleKit::SetupUI).to receive(:print_tenant_banner)
    end

    it 'does not clear the configurator when switching to another tenant' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return('globex')

      described_class.reset

      expect(ConsoleKit::TenantConfigurator).not_to have_received(:clear)
    end

    it 'clears the configurator when choosing no tenant' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return(:none)

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

      expect(described_class.current_tenant).to eq('globex')
    end

    it 'aborts if selection returns :abort' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return(:abort)

      described_class.reset

      expect(ConsoleKit::TenantConfigurator).not_to have_received(:clear)
    end

    it 'keeps current_tenant if aborted' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return(:abort)

      described_class.reset

      expect(described_class.current_tenant).to eq('acme')
    end

    context 'when no tenant was configured before the switch' do
      before do
        described_class.current_tenant = nil
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('globex')
      end

      it 'clears nothing, because there is nothing to clear' do
        described_class.reset

        expect(ConsoleKit::TenantConfigurator).not_to have_received(:clear)
      end

      it 'still configures the selected tenant' do
        described_class.reset

        expect(ConsoleKit::TenantConfigurator).to have_received(:configure_tenant).with('globex')
      end
    end
  end

  describe '.reapply' do
    it 're-applies the current tenant via TenantSwitch' do
      described_class.current_tenant = 'acme'
      allow(ConsoleKit::TenantSwitch).to receive(:call)

      described_class.reapply

      expect(ConsoleKit::TenantSwitch).to have_received(:call).with('acme')
    end
  end
end
