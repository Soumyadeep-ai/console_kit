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
      allow(ConsoleKit::Output).to receive(:print_error)
      allow(ConsoleKit::Output).to receive(:print_backtrace) if backtrace
      described_class.configure_tenant(tenant_key, tenants, context_class)
      expect(ConsoleKit::Output).to have_received(:print_error).with(a_string_matching(expected_message))
    end
  end

  describe '.configure_tenant' do
    subject(:configure) { described_class.configure_tenant(tenant_key, tenants, context_class) }

    context 'with valid tenant key' do
      it 'sets tenant_shard on context' do
        allow(ApplicationRecord).to receive(:establish_connection)
        allow(Mongoid).to receive(:override_client)
        allow(ConsoleKit::Output).to receive(:print_success)
        configure
        expect(context_class.tenant_shard).to eq('shard_acme')
      end

      it 'sets tenant_mongo_db on context' do
        allow(ApplicationRecord).to receive(:establish_connection)
        allow(Mongoid).to receive(:override_client)
        allow(ConsoleKit::Output).to receive(:print_success)
        configure
        expect(context_class.tenant_mongo_db).to eq('acme_db')
      end

      it 'sets partner_identifier on context' do
        allow(ApplicationRecord).to receive(:establish_connection)
        allow(Mongoid).to receive(:override_client)
        allow(ConsoleKit::Output).to receive(:print_success)
        configure
        expect(context_class.partner_identifier).to eq('ACME')
      end

      it 'establishes ActiveRecord connection' do
        allow(ApplicationRecord).to receive(:establish_connection)
        allow(Mongoid).to receive(:override_client)
        allow(ConsoleKit::Output).to receive(:print_success)
        configure
        expect(ApplicationRecord).to have_received(:establish_connection).with(:shard_acme)
      end

      it 'sets Mongoid client override' do
        allow(ApplicationRecord).to receive(:establish_connection)
        allow(Mongoid).to receive(:override_client)
        allow(ConsoleKit::Output).to receive(:print_success)
        configure
        expect(Mongoid).to have_received(:override_client).with('acme_db')
      end

      it 'prints success message' do
        allow(ApplicationRecord).to receive(:establish_connection)
        allow(Mongoid).to receive(:override_client)
        allow(ConsoleKit::Output).to receive(:print_success)
        configure
        expect(ConsoleKit::Output).to have_received(:print_success).with("Tenant set to: #{tenant_key}")
      end
    end

    context 'with missing tenant config' do
      let(:tenant_key) { 'missing' }
      let(:tenants) { { 'acme' => { constants: valid_constants } } }

      it 'prints error for missing config' do
        allow(ConsoleKit::Output).to receive(:print_error)
        configure
        expect(ConsoleKit::Output).to have_received(:print_error).with(/No configuration/)
      end

      it 'returns false' do
        allow(ConsoleKit::Output).to receive(:print_error)
        expect(configure).to be_falsey
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
        expect { configure }.not_to raise_error
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
        expect { configure }.not_to raise_error
      end
    end

    context 'when Mongoid is not defined' do
      before { hide_const('Mongoid') }

      it 'skips mongo client override without error' do
        expect { configure }.not_to raise_error
      end
    end

    context 'when configuration succeeds' do
      before do
        allow(ApplicationRecord).to receive(:establish_connection)
        allow(Mongoid).to receive(:override_client)
        allow(ConsoleKit::Output).to receive(:print_success)
      end

      it { is_expected.to be(true) }
    end
  end

  describe '.configuration_success=' do
    it 'calls mark_configured! on Context when set to truthy' do
      allow(ConsoleKit::Context).to receive(:mark_configured!)
      described_class.configuration_success = true
      expect(ConsoleKit::Context).to have_received(:mark_configured!)
    end

    it 'does not call mark_configured! when set to nil' do
      allow(ConsoleKit::Context).to receive(:mark_configured!)
      described_class.configuration_success = nil
      expect(ConsoleKit::Context).not_to have_received(:mark_configured!)
    end
  end

  describe '.current_tenant_key=' do
    it 'is a no-op shim that returns nil' do
      expect(described_class.send(:current_tenant_key=, :anything)).to be_nil
    end
  end

  describe '.configure_tenant with nil mongo_db' do
    before do
      allow(ApplicationRecord).to receive(:establish_connection)
      allow(ConsoleKit::Output).to receive(:print_success)
      allow(Mongoid).to receive(:override_client)
    end

    it 'skips Mongoid override when mongo_db is nil' do
      no_mongo = { tenant_key => { constants: { shard: 'shard_acme', mongo_db: nil, partner_code: 'ACME' } } }
      described_class.configure_tenant(tenant_key, no_mongo, context_class)
      expect(Mongoid).not_to have_received(:override_client)
    end
  end

  describe '.configure_tenant with empty mongo_db' do
    before do
      allow(ApplicationRecord).to receive(:establish_connection)
      allow(ConsoleKit::Output).to receive(:print_success)
      allow(Mongoid).to receive(:override_client)
    end

    it 'skips Mongoid override when mongo_db is empty string' do
      empty_mongo = { tenant_key => { constants: { shard: 'shard_acme', mongo_db: '', partner_code: 'ACME' } } }
      described_class.configure_tenant(tenant_key, empty_mongo, context_class)
      expect(Mongoid).not_to have_received(:override_client)
    end
  end

  describe '.clear' do
    before do
      context_class.tenant_shard = 'some_shard'
      context_class.tenant_mongo_db = 'some_db'
      context_class.partner_identifier = 'some_partner'
    end

    it 'resets tenant_shard to nil' do
      allow(ConsoleKit::Output).to receive(:print_info)
      described_class.clear(context_class)
      expect(context_class.tenant_shard).to be_nil
    end

    it 'resets tenant_mongo_db to nil' do
      allow(ConsoleKit::Output).to receive(:print_info)
      described_class.clear(context_class)
      expect(context_class.tenant_mongo_db).to be_nil
    end

    it 'resets partner_identifier to nil' do
      allow(ConsoleKit::Output).to receive(:print_info)
      described_class.clear(context_class)
      expect(context_class.partner_identifier).to be_nil
    end

    it 'prints cleared info message' do
      allow(ConsoleKit::Output).to receive(:print_info)
      described_class.clear(context_class)
      expect(ConsoleKit::Output).to have_received(:print_info).with('Tenant context has been cleared.')
    end

    it 'is idempotent' do
      allow(ConsoleKit::Output).to receive(:print_info)
      described_class.clear(context_class)
      expect { described_class.clear(context_class) }.not_to raise_error
    end
  end
end
