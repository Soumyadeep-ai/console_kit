# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit do
  let(:tenants) do
    {
      'acme' => { constants: { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME' } },
      'globex' => { constants: { shard: 'shard_globex', mongo_db: 'globex_db', partner_code: 'GBX' } }
    }
  end

  let(:context_class) do
    Class.new do
      class << self
        attr_accessor :tenant_shard, :tenant_mongo_db, :partner_identifier
      end
    end
  end

  before do
    described_class.configure do |config|
      config.tenants = tenants
      config.context_class = context_class
    end
  end

  describe '.configure' do
    it 'yields itself for config block' do
      yielded = nil
      ConsoleKit.configure { |conf| yielded = conf }
      expect(yielded).to eq(ConsoleKit)
    end
  end

  before do
    ConsoleKit.instance_variable_set(:@last_tenant, nil)
  end

  describe '.setup' do
    it 'sets up tenant successfully via TenantConfigurator' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
      expect(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).with('acme', tenants, context_class)
      expect(ConsoleKit::Output).to receive(:print_success).with(/Tenant initialized: acme/)
      ConsoleKit.setup
    end

    it 'sets @last_tenant after setup' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return('globex')
      allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant)
      allow(ConsoleKit::Output).to receive(:print_success)
      ConsoleKit.setup
      expect(ConsoleKit.last_tenant).to eq('globex')
    end

    it 'prints error when tenants is nil' do
      described_class.tenants = nil
      expect(ConsoleKit::Output).to receive(:print_error).with(/No tenants configured/)
      described_class.setup
    end

    it 'prints error when tenants are empty' do
      described_class.tenants = {}
      expect(ConsoleKit::Output).to receive(:print_error).with(/No tenants configured/)
      described_class.setup
    end

    it 'prints error if tenant selection returns nil' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return(nil)
      allow(ConsoleKit::Output).to receive(:print_success)
      expect(ConsoleKit::Output).to receive(:print_error).with(/No tenant selected/)
      ConsoleKit.setup
    end

    it 'rescues and prints setup error' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
      allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_raise(StandardError.new('Boom'))
      expect(ConsoleKit::Output).to receive(:print_error).with(/Error setting up tenant: Boom/)
      expect(ConsoleKit::Output).to receive(:print_backtrace)
      described_class.setup
    end

    context 'with single tenant & interactive off' do
      before do
        described_class.tenants = { 'solo' => tenants['acme'] }
        allow($stdin).to receive(:tty?).and_return(false) # Simulate non-interactive
      end

      it 'auto-picks the only tenant' do
        expect(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).with('solo', anything, anything)
        described_class.setup
      end
    end
  end
end
