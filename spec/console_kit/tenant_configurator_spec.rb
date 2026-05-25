# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::TenantConfigurator do
  let(:tenant_key) { 'acme' }
  let(:valid_constants) do
    { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME', redis_db: 1, elasticsearch_prefix: 'acme' }
  end
  let(:tenants) { { tenant_key => { constants: valid_constants } } }
  let(:context_class) do
    Struct.new(:tenant_shard, :tenant_mongo_db, :tenant_redis_db, :tenant_elasticsearch_prefix, :partner_identifier).new
  end

  before do
    # Stub configuration accessor
    allow(ConsoleKit.configuration).to receive_messages(tenants: tenants, context_class: context_class)
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
        allow(Mongoid).to receive(:override_database)
        allow(Mongoid).to receive(:override_client)
        allow(Mongoid::Config).to receive(:clients).and_return({})
        allow(ConsoleKit::Output).to receive(:print_success)
      end

      it 'establishes ActiveRecord connection with correct shard' do
        configure
        expect(ApplicationRecord).to have_received(:establish_connection).with(:shard_acme)
      end

      it 'overrides Mongoid database when mongo_db is not a named client' do
        configure
        expect(Mongoid).to have_received(:override_database).with('acme_db')
      end

      it 'overrides Mongoid named client when mongo_db matches a configured client' do
        allow(Mongoid::Config).to receive(:clients).and_return({ 'acme_db' => {} })
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

      it 'sets tenant_redis_db correctly' do
        configure
        expect(context_class.tenant_redis_db).to eq(1)
      end

      it 'sets tenant_elasticsearch_prefix correctly' do
        configure
        expect(context_class.tenant_elasticsearch_prefix).to eq('acme')
      end

      it 'returns true' do
        expect(configure).to be(true)
      end
    end

    context 'with partner_identifier case mismatch' do
      let(:valid_constants) do
        { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'acme', redis_db: 1, elasticsearch_prefix: 'acme' }
      end

      before do
        context_class.partner_identifier = 'ACME'
        allow(ApplicationRecord).to receive(:establish_connection)
        allow(Mongoid).to receive(:override_database)
        allow(Mongoid).to receive(:override_client)
        allow(Mongoid::Config).to receive(:clients).and_return({})
        allow(ConsoleKit::Output).to receive(:print_success)
        allow(ConsoleKit::Output).to receive(:print_warning)
      end

      it 'emits a case mismatch warning' do
        configure
        expect(ConsoleKit::Output).to have_received(:print_warning)
          .with(a_string_including('partner_identifier case mismatch'))
      end

      it 'mentions the existing value in warning' do
        configure
        expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('ACME'))
      end

      it 'mentions the configured value in warning' do
        configure
        expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('acme'))
      end

      it 'still applies the configured value' do
        configure
        expect(context_class.partner_identifier).to eq('acme')
      end
    end

    context 'with partner_identifier matching exactly' do
      before do
        context_class.partner_identifier = 'ACME'
        allow(ApplicationRecord).to receive(:establish_connection)
        allow(Mongoid).to receive(:override_database)
        allow(Mongoid).to receive(:override_client)
        allow(Mongoid::Config).to receive(:clients).and_return({})
        allow(ConsoleKit::Output).to receive(:print_success)
        allow(ConsoleKit::Output).to receive(:print_warning)
      end

      it 'does not emit a case mismatch warning' do
        configure
        expect(ConsoleKit::Output).not_to have_received(:print_warning)
          .with(a_string_including('case mismatch'))
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

    context 'when Mongoid.override_database fails' do
      before { allow(Mongoid).to receive(:override_database).and_raise('Mongo error') }

      it_behaves_like 'prints configuration error', expected_message: 'Failed to configure tenant'
      it_behaves_like 'prints backtrace'
    end

    context 'when Mongoid does not support override_database' do
      before do
        mongo_class = Class.new
        allow(mongo_class).to receive(:respond_to?).with(:override_database).and_return(false)
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
      allow(ApplicationRecord).to receive(:establish_connection)
      allow(Mongoid).to receive(:override_database)
      allow(Mongoid).to receive(:override_client)
      allow(Mongoid::Config).to receive(:clients).and_return({})
    end

    it 'prints info about clearing' do
      described_class.clear
      expect(ConsoleKit::Output).to have_received(:print_info).with('Tenant context has been cleared.')
    end

    it 'resets ActiveRecord connection' do
      described_class.clear
      expect(ApplicationRecord).to have_received(:establish_connection).with(no_args)
    end

    it 'resets Mongoid database override to nil' do
      described_class.clear
      expect(Mongoid).to have_received(:override_database).with(nil)
    end

    it 'resets Mongoid named client override to nil' do
      described_class.clear
      expect(Mongoid).to have_received(:override_client).with(nil)
    end

    it 'resets tenant_shard to nil' do
      described_class.clear
      expect(context_class.tenant_shard).to be_nil
    end

    it 'resets tenant_mongo_db to nil' do
      described_class.clear
      expect(context_class.tenant_mongo_db).to be_nil
    end

    it 'resets tenant_redis_db to nil' do
      described_class.clear
      expect(context_class.tenant_redis_db).to be_nil
    end

    it 'resets tenant_elasticsearch_prefix to nil' do
      described_class.clear
      expect(context_class.tenant_elasticsearch_prefix).to be_nil
    end

    it 'resets partner_identifier to nil' do
      described_class.clear
      expect(context_class.partner_identifier).to be_nil
    end

    it 'is idempotent' do
      expect { described_class.clear }.not_to raise_error
      described_class.clear
    end

    context 'when context_class is not set' do
      before { allow(ConsoleKit.configuration).to receive(:context_class).and_return(nil) }

      it 'does not raise error' do
        expect { described_class.clear }.not_to raise_error
      end
    end
  end

  describe '.validate_constants!' do
    it 'raises error if any required constant is missing' do
      constants = { mongo_db: 'db' } # missing shard, partner_code
      expect { described_class.send(:validate_constants!, constants) }
        .to raise_error(ConsoleKit::Error, /missing keys: shard, partner_code/)
    end

    it 'does not raise error if all required constants are present' do
      constants = { shard: 'shard', mongo_db: 'db', partner_code: 'code' }
      expect { described_class.send(:validate_constants!, constants) }.not_to raise_error
    end
  end

  describe 'ContextWrapper.for_context attribute detection' do
    let(:full_ctx) do
      Class.new do
        class << self
          attr_accessor :partner_identifier, :tenant_shard, :tenant_mongo_db, :tenant_redis_db,
                        :tenant_elasticsearch_prefix
        end
      end
    end

    it 'skips attributes the context class does not support' do
      ctx = Class.new { class << self; attr_accessor :partner_identifier, :tenant_shard; end }
      attrs = ConsoleKit::TenantConfigurator::ContextWrapper.for_context(ctx).attributes
      expect(attrs).to contain_exactly(:partner_identifier, :tenant_shard)
    end

    it 'includes all attributes when context supports them' do
      attrs = ConsoleKit::TenantConfigurator::ContextWrapper.for_context(full_ctx).attributes
      expect(attrs).to include(:partner_identifier, :tenant_shard, :tenant_mongo_db,
                               :tenant_redis_db, :tenant_elasticsearch_prefix)
    end
  end
end
