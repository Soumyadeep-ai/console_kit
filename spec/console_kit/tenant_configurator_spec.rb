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

    context 'with malformed constants' do
      let(:bad_tenants) { { 'acme' => {} } }

      it 'prints error when constants are missing' do
        expect(ConsoleKit::Output).to receive(:print_error).with(/Failed to configure tenant/)
        expect(ConsoleKit::Output).to receive(:print_backtrace)

        described_class.configure_tenant('acme', bad_tenants, context_class)
      end
    end

    context 'when ActiveRecord connection fails' do
      before do
        allow(ApplicationRecord).to receive(:establish_connection).and_raise('AR error')
      end

      it 'prints error and backtrace' do
        expect(ConsoleKit::Output).to receive(:print_error).with(/Failed to configure tenant/)
        expect(ConsoleKit::Output).to receive(:print_backtrace)

        described_class.configure_tenant('acme', tenants, context_class)
      end
    end

    context 'when Mongoid override fails' do
      before do
        allow(Mongoid).to receive(:override_client).and_raise('Mongo error')
      end

      it 'prints error and backtrace' do
        expect(ConsoleKit::Output).to receive(:print_error).with(/Failed to configure tenant/)
        expect(ConsoleKit::Output).to receive(:print_backtrace)

        described_class.configure_tenant('acme', tenants, context_class)
      end
    end

    context 'when Mongoid does not support override_client' do
      before do
        mongo_class = Class.new
        allow(mongo_class).to receive(:respond_to?).with(:override_client).and_return(false)
        stub_const('Mongoid', mongo_class)
      end

      it 'skips Mongoid client override without error' do
        expect { described_class.configure_tenant('acme', tenants, context_class) }.not_to raise_error
      end
    end
  end
end
