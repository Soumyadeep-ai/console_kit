# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit do
  let(:tenants) do
    {
      'acme' => { constants: { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME' } }
    }
  end

  let(:context_class) do
    Struct.new(:tenant_shard, :tenant_mongo_db, :partner_identifier).new
  end

  before do
    described_class.configure do |config|
      config.tenants = tenants
      config.context_class = context_class
    end
  end

  it 'sets up the tenant successfully' do
    expect(ConsoleKit::TenantConfigurator).to receive(:configure_tenant)
    expect(ConsoleKit::Output).to receive(:print_success).with(/Tenant initialized/)
    described_class.setup
  end

  it 'prints error when no tenants configured' do
    described_class.tenants = nil
    expect(ConsoleKit::Output).to receive(:print_error).with(/No tenants configured/)
    described_class.setup
  end
end
