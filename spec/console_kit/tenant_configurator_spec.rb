# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::TenantConfigurator do
  let(:tenant_key) { 'acme' }
  let(:valid_constants) { { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME' } }
  let(:tenants) { { tenant_key => { constants: valid_constants } } }
  let(:context_class) { Struct.new(:tenant_shard, :tenant_mongo_db, :partner_identifier).new }

  before do
    stub_const('ApplicationRecord', Class.new { def self.establish_connection(_arg); end })
    stub_const('Mongoid', Class.new { def self.override_client(_arg); end })
  end

  shared_examples 'prints configuration error' do |expected_message:, backtrace: false|
    it 'prints expected configuration error' do
      expect(ConsoleKit::Output).to receive(:print_error).with(a_string_matching(expected_message))
      expect(ConsoleKit::Output).to receive(:print_backtrace) if backtrace
      subject
    end
  end

  describe '.configure_tenant' do
    subject { described_class.configure_tenant(tenant_key, tenants, context_class) }

    context 'with valid tenant key' do
      it 'configures context and connections correctly' do
        expect(ApplicationRecord).to receive(:establish_connection).with(:shard_acme)
        expect(Mongoid).to receive(:override_client).with('acme_db')
        expect(ConsoleKit::Output).to receive(:print_success).with("Tenant set to: #{tenant_key}")

        subject

        expect(context_class.tenant_shard).to eq('shard_acme')
        expect(context_class.tenant_mongo_db).to eq('acme_db')
        expect(context_class.partner_identifier).to eq('ACME')
      end
    end

    context 'with missing tenant config' do
      let(:tenant_key) { 'missing' }
      let(:tenants) { { 'acme' => { constants: valid_constants } } }

      it 'prints error and returns false' do
        expect(ConsoleKit::Output).to receive(:print_error).with(/No configuration/)
        expect(subject).to be_falsey
      end
    end

    context 'with missing constants' do
      let(:tenants) { { tenant_key => {} } }

      it_behaves_like 'prints configuration error', expected_message: 'No configuration found for tenant'
    end

    context 'with nil constants' do
      let(:tenants) { { tenant_key => { constants: nil } } }

      it_behaves_like 'prints configuration error', expected_message: 'No configuration found for tenant'
    end

    context 'when ApplicationRecord.establish_connection fails' do
      before { allow(ApplicationRecord).to receive(:establish_connection).and_raise('AR error') }

      it_behaves_like 'prints configuration error', expected_message: 'Failed to configure tenant', backtrace: true
    end

    context 'when Mongoid.override_client fails' do
      before { allow(Mongoid).to receive(:override_client).and_raise('Mongo error') }

      it_behaves_like 'prints configuration error', expected_message: 'Failed to configure tenant', backtrace: true
    end

    context 'when Mongoid does not support override_client' do
      before do
        mongo_class = Class.new
        allow(mongo_class).to receive(:respond_to?).with(:override_client).and_return(false)
        stub_const('Mongoid', mongo_class)
      end

      it 'skips Mongoid override without error' do
        expect { subject }.not_to raise_error
      end
    end

    context 'with partial constants missing' do
      # missing partner_code
      let(:tenants) { { tenant_key => { constants: { shard: 'shard_acme' } } } }

      it_behaves_like 'prints configuration error', expected_message: 'Failed to configure tenant', backtrace: true
    end

    context 'when ApplicationRecord is not defined' do
      before { hide_const('ApplicationRecord') }

      it 'skips establish_connection without error' do
        expect { subject }.not_to raise_error
      end
    end

    context 'when Mongoid is not defined' do
      before { hide_const('Mongoid') }

      it 'skips mongo client override without error' do
        expect { subject }.not_to raise_error
      end
    end

    context 'returns true on successful configuration' do
      it { is_expected.to be(true) }
    end
  end

  describe '.clear' do
    before do
      context_class.tenant_shard = 'some_shard'
      context_class.tenant_mongo_db = 'some_db'
      context_class.partner_identifier = 'some_partner'
    end

    it 'resets context values to nil and prints info' do
      expect(ConsoleKit::Output).to receive(:print_info).with('Tenant context has been cleared.')

      described_class.clear(context_class)

      expect(context_class.tenant_shard).to be_nil
      expect(context_class.tenant_mongo_db).to be_nil
      expect(context_class.partner_identifier).to be_nil
    end

    it 'is idempotent' do
      described_class.clear(context_class)
      expect { described_class.clear(context_class) }.not_to raise_error
    end
  end
end
