# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit do
  include IntegrationTestHelper

  def self.build_context_class(*attrs)
    Class.new.tap do |klass|
      klass.singleton_class.attr_accessor(*attrs)
    end
  end

  # A base class that really moves its pool onto the configuration it is given,
  # so SqlConnectionHandler#verify! can read the identity back honestly instead
  # of being stubbed into agreement.
  def self.build_application_record
    ActiveRecordMock.plain_base(configs: %w[primary shard_acme shard_globex])
  end

  shared_context 'with full context class' do
    let(:context_class) do
      self.class.build_context_class(
        :tenant_shard, :tenant_mongo_db, :tenant_redis_db,
        :tenant_elasticsearch_prefix, :partner_identifier
      )
    end
  end

  shared_context 'with full tenant config' do
    include_context 'with full context class'

    let(:tenants) do
      {
        'acme' => {
          constants: { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME',
                       redis_db: 2, elasticsearch_prefix: 'acme_es' }
        },
        'globex' => {
          constants: { shard: 'shard_globex', mongo_db: 'globex_db', partner_code: 'GBX',
                       redis_db: 3, elasticsearch_prefix: 'globex_es' }
        }
      }
    end

    before do
      described_class.configure do |config|
        config.tenants = tenants
        config.context_class = context_class
        config.pretty_output = false
      end

      stub_const('ApplicationRecord', self.class.build_application_record)
      allow(ApplicationRecord).to receive(:establish_connection).and_call_original
    end
  end

  describe 'tenant lifecycle' do
    include_context 'with full tenant config'

    describe 'configure → verify → clear cycle' do
      it 'sets partner_identifier from the tenant constants' do
        ConsoleKit::TenantConfigurator.configure_tenant('acme')

        expect(context_class.partner_identifier).to eq('ACME')
      end

      it 'sets tenant_shard from the tenant constants' do
        ConsoleKit::TenantConfigurator.configure_tenant('acme')

        expect(context_class.tenant_shard).to eq('shard_acme')
      end

      it 'calls establish_connection with the configured shard' do
        ConsoleKit::TenantConfigurator.configure_tenant('acme')

        expect(ApplicationRecord).to have_received(:establish_connection).with(:shard_acme)
      end

      it 'leaves the SQL pool on the configured shard' do
        ConsoleKit::TenantConfigurator.configure_tenant('acme')

        expect(ApplicationRecord.connection_pool.db_config.name).to eq('shard_acme')
      end

      it 'clears partner_identifier on clear' do
        ConsoleKit::TenantConfigurator.configure_tenant('acme')
        ConsoleKit::TenantConfigurator.clear

        expect(context_class.partner_identifier).to be_nil
      end

      it 'clears tenant_shard on clear' do
        ConsoleKit::TenantConfigurator.configure_tenant('acme')
        ConsoleKit::TenantConfigurator.clear

        expect(context_class.tenant_shard).to be_nil
      end

      it 'resets SQL connection to default on clear' do
        ConsoleKit::TenantConfigurator.configure_tenant('acme')
        ConsoleKit::TenantConfigurator.clear

        expect(ApplicationRecord).to have_received(:establish_connection).with(no_args)
      end

      it 'reports no configuration before a tenant is configured' do
        expect(ConsoleKit::TenantConfigurator.configuration_success).to be_falsey
      end

      it 'reports a successful configuration once a tenant is configured' do
        ConsoleKit::TenantConfigurator.configure_tenant('acme')

        expect(ConsoleKit::TenantConfigurator.configuration_success).to be true
      end

      it 'remains successful after configuring the same tenant twice' do
        ConsoleKit::TenantConfigurator.configure_tenant('acme')
        ConsoleKit::TenantConfigurator.configure_tenant('acme')

        expect(ConsoleKit::TenantConfigurator.configuration_success).to be true
      end

      it 'does not re-establish the connection when configuring the same tenant twice' do
        ConsoleKit::TenantConfigurator.configure_tenant('acme')
        RSpec::Mocks.space.proxy_for(ApplicationRecord).reset
        allow(ApplicationRecord).to receive(:establish_connection).and_call_original
        ConsoleKit::TenantConfigurator.configure_tenant('acme')

        expect(ApplicationRecord).not_to have_received(:establish_connection)
      end

      it 'does not crash when clearing an already cleared context' do
        ConsoleKit::TenantConfigurator.clear
        expect { ConsoleKit::TenantConfigurator.clear }.not_to raise_error
      end

      it 'does not re-run connection handlers if already cleared' do
        ConsoleKit::TenantConfigurator.clear
        # Reset mocks to track new calls
        allow(ApplicationRecord).to receive(:establish_connection).and_call_original

        ConsoleKit::TenantConfigurator.clear
        expect(ApplicationRecord).not_to have_received(:establish_connection)
      end
    end

    describe 'tenant switching' do
      let(:establish_calls) { [] }

      before do
        allow(ApplicationRecord).to receive(:establish_connection).and_wrap_original do |original, *args|
          establish_calls << args
          original.call(*args)
        end
        ConsoleKit::TenantConfigurator.configure_tenant('acme')
        ConsoleKit::TenantConfigurator.clear
        ConsoleKit::TenantConfigurator.configure_tenant('globex')
      end

      it 'replaces the partner identifier' do
        expect(context_class.partner_identifier).to eq('GBX')
      end

      it 'replaces the tenant shard' do
        expect(context_class.tenant_shard).to eq('shard_globex')
      end

      it 'calls establish_connection for both tenants in order' do
        expect(establish_calls).to eq([[:shard_acme], [], [:shard_globex]])
      end
    end

    describe 'error handling' do
      it 'sets configuration_success to false for missing tenant' do
        ConsoleKit::TenantConfigurator.configure_tenant('nonexistent')

        expect(ConsoleKit::TenantConfigurator.configuration_success).to be_falsey
      end

      it 'does not modify context attributes for missing tenant' do
        ConsoleKit::TenantConfigurator.configure_tenant('acme')
        ConsoleKit::TenantConfigurator.configure_tenant('nonexistent')

        expect(context_class.partner_identifier).to eq('ACME')
      end

      it 'handles establish_connection failure gracefully' do
        allow(ApplicationRecord).to receive(:establish_connection).and_raise(StandardError, 'connection failed')

        ConsoleKit::TenantConfigurator.configure_tenant('acme')

        expect(ConsoleKit::TenantConfigurator.configuration_success).to be_falsey
      end

      it 'handles tenant config with invalid constants type' do
        allow(described_class.configuration).to receive(:tenants).and_return({ 'bad' => { constants: 'not a hash' } })

        ConsoleKit::TenantConfigurator.configure_tenant('bad')

        expect(ConsoleKit::TenantConfigurator.configuration_success).to be_falsey
      end
    end

    describe 'missing constants validation' do
      let(:tenants) do
        { 'bad' => { constants: { shard: 'shard_bad' } } }
      end

      it 'rejects tenant config missing required constants' do
        ConsoleKit::TenantConfigurator.configure_tenant('bad')

        expect(ConsoleKit::TenantConfigurator.configuration_success).to be_falsey
      end
    end
  end

  describe 'setup' do
    include_context 'with full context class'

    let(:tenants) do
      { 'acme' => { constants: { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME' } } }
    end

    before do
      described_class.configure do |config|
        config.tenants = tenants
        config.context_class = context_class
        config.pretty_output = false
      end

      stub_const('ApplicationRecord', self.class.build_application_record)
      allow(ApplicationRecord).to receive(:establish_connection).and_call_original
    end

    describe 'auto-select with single tenant' do
      before { ConsoleKit::Setup.setup }

      it 'auto-selects the only tenant' do
        expect(ConsoleKit::Setup.current_tenant).to eq('acme')
      end

      it 'reports the setup as successful' do
        expect(ConsoleKit::Setup.tenant_setup_successful?).to be true
      end

      it 'sets partner_identifier from the tenant constants' do
        expect(context_class.partner_identifier).to eq('ACME')
      end

      it 'sets tenant_shard from the tenant constants' do
        expect(context_class.tenant_shard).to eq('shard_acme')
      end

      it 'is idempotent — second call is a no-op' do
        ConsoleKit::Setup.setup

        expect(ApplicationRecord).to have_received(:establish_connection).once
      end
    end

    # Since 1.5.0 a re-applied switch still runs every stage, but the SQL
    # strategy skips `establish_connection` when the pool already resolves to
    # the shard being asked for, so re-applying no longer churns the pool.
    describe 'reapply silently re-applies current tenant' do
      let(:reapply_output) do
        ConsoleKit::Setup.setup
        capture_all_output { ConsoleKit::Setup.reapply }
      end

      it 'produces no output' do
        expect(reapply_output).to be_empty
      end

      it 'leaves the SQL pool on the tenant shard' do
        reapply_output

        expect(ApplicationRecord.connection_pool.db_config.name).to eq('shard_acme')
      end

      it 'does not re-establish a connection that is already on the shard' do
        reapply_output

        expect(ApplicationRecord).to have_received(:establish_connection).once
      end
    end
  end

  describe 'connection handler discovery' do
    include_context 'with full context class'

    before do
      described_class.configure do |config|
        config.tenants = { 'acme' => { constants: { shard: 'shard_acme', partner_code: 'ACME' } } }
        config.context_class = context_class
        config.pretty_output = false
      end
    end

    context 'when ApplicationRecord is defined' do
      before { stub_const('ApplicationRecord', self.class.build_application_record) }

      it 'includes SQL handler' do
        handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)

        expect(handlers.map(&:class)).to include(ConsoleKit::Connections::SqlConnectionHandler)
      end

      it 'passes context through to each handler' do
        handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)

        handlers.each { |handler| expect(handler.context).to eq(context_class) }
      end
    end

    it 'excludes SQL handler when ApplicationRecord is not defined' do
      described_class.configuration.sql_base_class = 'NonExistentRecord'

      handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)

      expect(handlers.map(&:class)).not_to include(ConsoleKit::Connections::SqlConnectionHandler)
    end

    it 'includes Mongo handler when Mongoid is defined' do
      stub_const('Mongoid', Module.new)

      handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)

      expect(handlers.map(&:class)).to include(ConsoleKit::Connections::MongoConnectionHandler)
    end

    it 'excludes Mongo handler when Mongoid is not defined' do
      hide_const('Mongoid') if defined?(Mongoid)

      handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)

      expect(handlers.map(&:class)).not_to include(ConsoleKit::Connections::MongoConnectionHandler)
    end

    it 'includes Redis handler when Redis is defined' do
      handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)

      expect(handlers.map(&:class)).to include(ConsoleKit::Connections::RedisConnectionHandler)
    end

    it 'includes Elasticsearch handler when Elasticsearch is defined' do
      handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)

      expect(handlers.map(&:class)).to include(ConsoleKit::Connections::ElasticsearchConnectionHandler)
    end
  end

  describe 'Elasticsearch thread-local prefix' do
    let(:context_class) do
      self.class.build_context_class(:tenant_elasticsearch_prefix, :partner_identifier)
    end

    before do
      described_class.configure do |config|
        config.tenants = {
          'acme' => { constants: { shard: 'shard_acme', partner_code: 'ACME', elasticsearch_prefix: 'acme_idx' } }
        }
        config.context_class = context_class
        config.pretty_output = false
      end
    end

    after { Thread.current[:console_kit_elasticsearch_prefix] = nil }

    context 'when tenant has an elasticsearch prefix' do
      before do
        context_class.tenant_elasticsearch_prefix = 'acme_idx'
        ConsoleKit::Connections::ElasticsearchConnectionHandler.new(context_class).connect
      end

      it 'sets thread-local prefix when tenant is configured' do
        expect(Thread.current[:console_kit_elasticsearch_prefix]).to eq('acme_idx')
      end

      it 'clears thread-local prefix when tenant is cleared' do
        context_class.tenant_elasticsearch_prefix = nil
        ConsoleKit::Connections::ElasticsearchConnectionHandler.new(context_class).connect

        expect(Thread.current[:console_kit_elasticsearch_prefix]).to be_nil
      end
    end

    context 'when Elasticsearch::Model is available' do
      let(:es_model) do
        Module.new do
          class << self
            attr_accessor :index_name_prefix
          end
        end
      end

      before do
        stub_const('Elasticsearch::Model', es_model)
        context_class.tenant_elasticsearch_prefix = 'acme_idx'
        ConsoleKit::Connections::ElasticsearchConnectionHandler.new(context_class).connect
      end

      it 'sets Elasticsearch::Model.index_name_prefix' do
        expect(Elasticsearch::Model.index_name_prefix).to eq('acme_idx')
      end
    end
  end

  describe 'dashboard' do
    let(:context_class) do
      self.class.build_context_class(:tenant_shard, :partner_identifier)
    end
    let(:connected_diag) { ->(name) { { name: name, status: :connected, latency_ms: 10, details: {} } } }
    # Diagnostics keys its per-thread row cache by backend, so every handler
    # double has to answer #backend_key as well as #safe_diagnostics.
    let(:stub_handlers) do
      [
        instance_double(ConsoleKit::Connections::SqlConnectionHandler,
                        backend_key: :sql, safe_diagnostics: connected_diag.call('SQL')),
        instance_double(ConsoleKit::Connections::ElasticsearchConnectionHandler,
                        backend_key: :elasticsearch, safe_diagnostics: connected_diag.call('Elasticsearch')),
        instance_double(ConsoleKit::Connections::MongoConnectionHandler,
                        backend_key: :mongo, safe_diagnostics: connected_diag.call('Mongo')),
        instance_double(ConsoleKit::Connections::RedisConnectionHandler,
                        backend_key: :redis, safe_diagnostics: connected_diag.call('Redis'))
      ]
    end

    let(:pool) { double(size: 5) }
    let(:conn) { double(adapter_name: 'PostgreSQL', execute: true, select_value: 'PostgreSQL 14.0') }

    before do
      stub_const('ApplicationRecord', self.class.build_application_record)

      described_class.configure do |config|
        config.tenants = { 'acme' => { constants: { shard: 'shard_acme', partner_code: 'ACME' } } }
        config.context_class = context_class
        config.pretty_output = false
      end
    end

    context 'when all handlers report connected status' do
      before do
        allow(ApplicationRecord).to receive_messages(connection: conn, connection_pool: pool)
        allow(ConsoleKit::Connections::ConnectionManager)
          .to receive(:available_handlers)
          .and_return(stub_handlers)
      end

      it 'renders SQL in the dashboard table' do
        output = capture_all_output { ConsoleKit::Connections::Dashboard.display }
        expect(output).to include('SQL')
      end

      it 'renders Connected status in the dashboard table' do
        output = capture_all_output { ConsoleKit::Connections::Dashboard.display }
        expect(output).to include('Connected')
      end
    end

    # Pre-1.5 the dashboard proved a broken SQL connection by having
    # ApplicationRecord.connection raise. The default :basic level issues no
    # query at all now, so a broken connection is invisible to it: the honest
    # error row is a backend that cannot even report its identity.
    context 'when a backend cannot report its identity' do
      before { allow(Mongoid).to receive(:default_client).and_raise(StandardError, 'timeout') }

      it 'names the failing backend in the dashboard table' do
        output = capture_all_output { ConsoleKit::Connections::Dashboard.display }

        expect(output).to include('MongoDB')
      end

      it 'renders an error status for it' do
        output = capture_all_output { ConsoleKit::Connections::Dashboard.display }

        expect(output).to include('Error')
      end
    end

    context 'when the SQL connection is broken' do
      before { allow(ApplicationRecord).to receive(:connection).and_raise(StandardError, 'timeout') }

      it 'still reports SQL as connected, because :basic diagnostics query nothing' do
        output = capture_all_output { ConsoleKit::Connections::Dashboard.display }

        expect(output).to include('Connected')
      end

      it 'never asks the base class for a connection' do
        capture_all_output { ConsoleKit::Connections::Dashboard.display }

        expect(ApplicationRecord).not_to have_received(:connection)
      end
    end
  end
end
