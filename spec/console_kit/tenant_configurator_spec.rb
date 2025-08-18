# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::TenantConfigurator do
  let(:tenant_key) { 'acme' }
  let(:valid_constants) { { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME' } }
  let(:tenants) { { tenant_key => { constants: valid_constants } } }
  let(:context_class) { Struct.new(:tenant_shard, :tenant_mongo_db, :partner_identifier).new }

  before do
    # Stub configuration accessor
    allow(ConsoleKit.configuration).to receive_messages(tenants: tenants, context_class: context_class)

    stub_const('ApplicationRecord', Class.new { def self.establish_connection(_arg); end })
    stub_const('Mongoid', Class.new { def self.override_client(_arg); end })
  end

  shared_examples 'prints configuration error' do |expected_message:|
    it 'prints expected configuration error' do
      allow(ConsoleKit::Output).to receive(:print_error)
      subject
      expect(ConsoleKit::Output).to have_received(:print_error).with(a_string_matching(expected_message))
    end
  end

  shared_examples 'prints backtrace' do
    it 'prints the backtrace' do
      allow(ConsoleKit::Output).to receive(:print_backtrace)
      subject
      expect(ConsoleKit::Output).to have_received(:print_backtrace)
    end
  end

  describe '.configure_tenant' do
    subject(:configure) { described_class.configure_tenant(tenant_key) }

    context 'with valid tenant key' do
      before do
        allow(ApplicationRecord).to receive(:establish_connection)
        allow(Mongoid).to receive(:override_client)
        allow(ConsoleKit::Output).to receive(:print_success)
      end

      it 'establishes ActiveRecord connection with correct shard' do
        configure
        expect(ApplicationRecord).to have_received(:establish_connection).with(:shard_acme)
      end

      it 'overrides Mongoid client with correct DB' do
        configure
        expect(Mongoid).to have_received(:override_client).with('acme_db')
      end

      it 'prints success message' do
        configure
        expect(ConsoleKit::Output).to have_received(:print_success).with("Tenant set to: #{tenant_key}")
      end

      it 'sets tenant_shard correctly' do
        configure
        expect(context_class.tenant_shard).to eq('shard_acme')
      end

      it 'sets tenant_mongo_db correctly' do
        configure
        expect(context_class.tenant_mongo_db).to eq('acme_db')
      end

      it 'sets partner_identifier correctly' do
        configure
        expect(context_class.partner_identifier).to eq('ACME')
      end

      it 'returns true' do
        expect(configure).to be(true)
      end
    end

    context 'with missing tenant config' do
      let(:tenant_key) { 'missing' }

      before do
        allow(ConsoleKit.configuration).to receive(:tenants).and_return({ 'acme' => { constants: valid_constants } })
        allow(ConsoleKit::Output).to receive(:print_error)
      end

      it 'prints error' do
        configure
        expect(ConsoleKit::Output).to have_received(:print_error).with(/No configuration/)
      end

      it 'returns false' do
        expect(configure).to be_falsey
      end
    end

    context 'with missing constants' do
      before { allow(ConsoleKit.configuration).to receive(:tenants).and_return({ tenant_key => {} }) }

      it_behaves_like 'prints configuration error', expected_message: 'No configuration found for tenant'
    end

    context 'with nil constants' do
      let(:tenants) { { tenant_key => { constants: nil } } }

      it_behaves_like 'prints configuration error', expected_message: 'No configuration found for tenant'
    end

    context 'when ApplicationRecord.establish_connection fails' do
      before { allow(ApplicationRecord).to receive(:establish_connection).and_raise('AR error') }

      it_behaves_like 'prints configuration error', expected_message: 'Failed to configure tenant'
      it_behaves_like 'prints backtrace'
    end

    context 'when Mongoid.override_client fails' do
      before { allow(Mongoid).to receive(:override_client).and_raise('Mongo error') }

      it_behaves_like 'prints configuration error', expected_message: 'Failed to configure tenant'
      it_behaves_like 'prints backtrace'
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
      before do
        allow(ConsoleKit.configuration).to receive(:tenants)
          .and_return({ tenant_key => { constants: { shard: 'shard_acme' } } })
      end

      it_behaves_like 'prints configuration error', expected_message: 'Failed to configure tenant'
      it_behaves_like 'prints backtrace'
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
      it { is_expected.to be(true) }
    end

    it 'does not raise error' do
      expect { configure }.not_to raise_error
    end
  end

  describe '.clear' do
    before do
      allow(ConsoleKit.configuration).to receive(:context_class).and_return(context_class)
      context_class.tenant_shard = 'some_shard'
      context_class.tenant_mongo_db = 'some_db'
      context_class.partner_identifier = 'some_partner'
      allow(ConsoleKit::Output).to receive(:print_info)
    end

    it 'prints info about clearing' do
      described_class.clear
      expect(ConsoleKit::Output).to have_received(:print_info).with('Tenant context has been cleared.')
    end

    it 'resets tenant_shard to nil' do
      described_class.clear
      expect(context_class.tenant_shard).to be_nil
    end

    it 'resets tenant_mongo_db to nil' do
      described_class.clear
      expect(context_class.tenant_mongo_db).to be_nil
    end

    it 'resets partner_identifier to nil' do
      described_class.clear
      expect(context_class.partner_identifier).to be_nil
    end

    it 'is idempotent' do
      expect { described_class.clear }.not_to raise_error
      described_class.clear
    end
  end
end
