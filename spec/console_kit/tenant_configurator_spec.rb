# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::TenantConfigurator do
  let(:tenants) do
    {
      'acme' => {
        constants: {
          shard: 'shard_acme',
          mongo_db: 'acme_db',
          partner_code: 'ACME'
        }
      }
    }
  end

  let(:context_class) do
    Struct.new(:tenant_shard, :tenant_mongo_db, :partner_identifier).new
  end

  before do
    stub_const('ApplicationRecord', Class.new do
      def self.establish_connection(arg); end
    end)

    stub_const('Mongoid', Class.new do
      def self.override_client(arg); end
    end)
  end

  it 'configures context and connections correctly' do
    expect(ApplicationRecord).to receive(:establish_connection).with(:shard_acme)
    expect(Mongoid).to receive(:override_client).with('acme_db')

    described_class.configure_tenant('acme', tenants, context_class)

    expect(context_class.tenant_shard).to eq('shard_acme')
    expect(context_class.tenant_mongo_db).to eq('acme_db')
    expect(context_class.partner_identifier).to eq('ACME')
  end

  it 'prints error if tenant config is missing' do
    expect(ConsoleKit::Output).to receive(:print_error).with(/No configuration/)
    described_class.configure_tenant('missing', tenants, context_class)
  end
end
