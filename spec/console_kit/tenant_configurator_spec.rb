# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::TenantConfigurator do
  let(:tenants) { { 'acme' => { constants: { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME' } } } }

  let(:context_class) { Struct.new(:tenant_shard, :tenant_mongo_db, :partner_identifier).new }

  before do
    stub_const('ApplicationRecord', Class.new { def self.establish_connection(_arg); end })
    stub_const('Mongoid', Class.new { def self.override_client(_arg); end })
  end

  describe '.configure_tenant' do
    context 'with valid tenant key' do
      it 'configures context and connections correctly' do
        expect(ApplicationRecord).to receive(:establish_connection).with(:shard_acme)
        expect(Mongoid).to receive(:override_client).with('acme_db')

        described_class.configure_tenant('acme', tenants, context_class)

        expect(context_class.tenant_shard).to eq('shard_acme')
        expect(context_class.tenant_mongo_db).to eq('acme_db')
        expect(context_class.partner_identifier).to eq('ACME')
      end
    end

    context 'with missing tenant config' do
      it 'prints error' do
        expect(ConsoleKit::Output).to receive(:print_error).with(/No configuration/)
        described_class.configure_tenant('missing', tenants, context_class)
      end
    end
  end
end
