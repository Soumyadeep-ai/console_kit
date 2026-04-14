# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Tenant lifecycle integration' do
  # Real context class — no mocks, actual struct with mutable attributes
  let(:context_class) do
    Class.new do
      class << self
        attr_accessor :tenant_shard, :tenant_mongo_db, :tenant_redis_db,
                      :tenant_elasticsearch_prefix, :partner_identifier
      end
    end
  end

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
    ConsoleKit.configure do |config|
      config.tenants = tenants
      config.context_class = context_class
      config.pretty_output = false
    end

    # Minimal external dependency stubs — only external systems that aren't present in test env
    stub_const('ApplicationRecord', Class.new do
      def self.establish_connection(_arg = nil); end
      def self.connection_pool
        @connection_pool ||= Class.new { def disconnect!; end }.new
      end
    end)
    allow(ApplicationRecord).to receive(:establish_connection).and_call_original
  end

  describe 'configure → verify → clear cycle' do
    it 'configures tenant and sets all context attributes' do
      ConsoleKit::TenantConfigurator.configure_tenant('acme')

      expect(context_class.partner_identifier).to eq('ACME')
      expect(context_class.tenant_shard).to eq('shard_acme')
    end

    it 'calls establish_connection with the configured shard' do
      ConsoleKit::TenantConfigurator.configure_tenant('acme')

      expect(ApplicationRecord).to have_received(:establish_connection).with(:shard_acme)
    end

    it 'clears all context attributes on clear' do
      ConsoleKit::TenantConfigurator.configure_tenant('acme')
      ConsoleKit::TenantConfigurator.clear

      expect(context_class.partner_identifier).to be_nil
      expect(context_class.tenant_shard).to be_nil
    end

    it 'resets SQL connection to default on clear' do
      ConsoleKit::TenantConfigurator.configure_tenant('acme')
      ConsoleKit::TenantConfigurator.clear

      expect(ApplicationRecord).to have_received(:establish_connection).with(no_args)
    end

    it 'tracks configuration_success state correctly' do
      expect(ConsoleKit::TenantConfigurator.configuration_success).to be_falsey

      ConsoleKit::TenantConfigurator.configure_tenant('acme')
      expect(ConsoleKit::TenantConfigurator.configuration_success).to be true
    end
  end

  describe 'tenant switching' do
    it 'replaces one tenant with another' do
      ConsoleKit::TenantConfigurator.configure_tenant('acme')
      expect(context_class.partner_identifier).to eq('ACME')
      expect(context_class.tenant_shard).to eq('shard_acme')

      ConsoleKit::TenantConfigurator.clear
      ConsoleKit::TenantConfigurator.configure_tenant('globex')

      expect(context_class.partner_identifier).to eq('GBX')
      expect(context_class.tenant_shard).to eq('shard_globex')
    end

    it 'calls establish_connection for both tenants in order' do
      ConsoleKit::TenantConfigurator.configure_tenant('acme')
      ConsoleKit::TenantConfigurator.clear
      ConsoleKit::TenantConfigurator.configure_tenant('globex')

      expect(ApplicationRecord).to have_received(:establish_connection).with(:shard_acme).ordered
      expect(ApplicationRecord).to have_received(:establish_connection).with(no_args).ordered
      expect(ApplicationRecord).to have_received(:establish_connection).with(:shard_globex).ordered
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
  end

  describe 'missing constants validation' do
    let(:tenants) do
      { 'bad' => { constants: { shard: 'shard_bad' } } } # missing partner_code
    end

    it 'rejects tenant config missing required constants' do
      ConsoleKit::TenantConfigurator.configure_tenant('bad')

      expect(ConsoleKit::TenantConfigurator.configuration_success).to be_falsey
    end
  end
end

RSpec.describe 'Setup integration' do
  let(:context_class) do
    Class.new do
      class << self
        attr_accessor :tenant_shard, :tenant_mongo_db, :tenant_redis_db,
                      :tenant_elasticsearch_prefix, :partner_identifier
      end
    end
  end

  let(:tenants) do
    {
      'acme' => { constants: { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME' } }
    }
  end

  before do
    ConsoleKit.configure do |config|
      config.tenants = tenants
      config.context_class = context_class
      config.pretty_output = false
    end

    stub_const('ApplicationRecord', Class.new do
      def self.establish_connection(_arg = nil); end
      def self.connection_pool
        @connection_pool ||= Class.new { def disconnect!; end }.new
      end
    end)
    allow(ApplicationRecord).to receive(:establish_connection).and_call_original
  end

  describe 'auto-select with single tenant' do
    it 'auto-selects and configures the only tenant' do
      ConsoleKit::Setup.setup

      expect(ConsoleKit::Setup.current_tenant).to eq('acme')
      expect(ConsoleKit::Setup.tenant_setup_successful?).to be true
      expect(context_class.partner_identifier).to eq('ACME')
      expect(context_class.tenant_shard).to eq('shard_acme')
    end

    it 'is idempotent — second call is a no-op' do
      ConsoleKit::Setup.setup
      ConsoleKit::Setup.setup

      expect(ApplicationRecord).to have_received(:establish_connection).once
    end
  end

  describe 'reapply silently re-applies current tenant' do
    it 'reconfigures without output' do
      ConsoleKit::Setup.setup

      output = capture_output { ConsoleKit::Setup.reapply }

      # Called twice: once during setup, once during reapply
      expect(ApplicationRecord).to have_received(:establish_connection).with(:shard_acme).twice
      expect(output).to be_empty
    end
  end

  def capture_output
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end

RSpec.describe 'Connection handler integration' do
  let(:context_class) do
    Class.new do
      class << self
        attr_accessor :tenant_shard, :tenant_mongo_db, :tenant_redis_db,
                      :tenant_elasticsearch_prefix, :partner_identifier
      end
    end
  end

  before do
    ConsoleKit.configure do |config|
      config.tenants = { 'acme' => { constants: { shard: 'shard_acme', partner_code: 'ACME' } } }
      config.context_class = context_class
      config.pretty_output = false
    end
  end

  describe 'ConnectionManager discovers handlers based on defined constants' do
    it 'includes SQL handler when ApplicationRecord is defined' do
      stub_const('ApplicationRecord', Class.new do
        def self.establish_connection(*); end
        def self.connection_pool
          @connection_pool ||= Class.new { def disconnect!; end }.new
        end
      end)

      handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)
      handler_types = handlers.map(&:class)

      expect(handler_types).to include(ConsoleKit::Connections::SqlConnectionHandler)
    end

    it 'excludes SQL handler when ApplicationRecord is not defined' do
      ConsoleKit.configuration.sql_base_class = 'NonExistentRecord'

      handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)
      handler_types = handlers.map(&:class)

      expect(handler_types).not_to include(ConsoleKit::Connections::SqlConnectionHandler)
    end

    it 'includes Mongo handler when Mongoid is defined' do
      stub_const('Mongoid', Module.new)

      handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)
      handler_types = handlers.map(&:class)

      expect(handler_types).to include(ConsoleKit::Connections::MongoConnectionHandler)
    end

    it 'excludes Mongo handler when Mongoid is not defined' do
      hide_const('Mongoid') if defined?(Mongoid)

      handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)
      handler_types = handlers.map(&:class)

      expect(handler_types).not_to include(ConsoleKit::Connections::MongoConnectionHandler)
    end

    it 'includes Redis handler when Redis is defined' do
      stub_const('Redis', Class.new)

      handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)
      handler_types = handlers.map(&:class)

      expect(handler_types).to include(ConsoleKit::Connections::RedisConnectionHandler)
    end

    it 'includes Elasticsearch handler when Elasticsearch is defined' do
      stub_const('Elasticsearch', Module.new)

      handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)
      handler_types = handlers.map(&:class)

      expect(handler_types).to include(ConsoleKit::Connections::ElasticsearchConnectionHandler)
    end

    it 'passes context through to each handler' do
      stub_const('ApplicationRecord', Class.new do
        def self.establish_connection(*); end
        def self.connection_pool
          @connection_pool ||= Class.new { def disconnect!; end }.new
        end
      end)

      handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)

      handlers.each do |handler|
        expect(handler.context).to eq(context_class)
      end
    end
  end
end

RSpec.describe 'Elasticsearch thread-local prefix integration' do
  let(:context_class) do
    Class.new do
      class << self
        attr_accessor :tenant_elasticsearch_prefix, :partner_identifier
      end
    end
  end

  before do
    stub_const('Elasticsearch', Module.new)
    ConsoleKit.configure do |config|
      config.tenants = {
        'acme' => { constants: { shard: 'shard_acme', partner_code: 'ACME', elasticsearch_prefix: 'acme_idx' } }
      }
      config.context_class = context_class
      config.pretty_output = false
    end
  end

  after { Thread.current[:console_kit_elasticsearch_prefix] = nil }

  it 'sets thread-local prefix when tenant is configured' do
    context_class.tenant_elasticsearch_prefix = 'acme_idx'
    handler = ConsoleKit::Connections::ElasticsearchConnectionHandler.new(context_class)
    handler.connect

    expect(Thread.current[:console_kit_elasticsearch_prefix]).to eq('acme_idx')
  end

  it 'clears thread-local prefix when tenant is cleared' do
    context_class.tenant_elasticsearch_prefix = 'acme_idx'
    handler = ConsoleKit::Connections::ElasticsearchConnectionHandler.new(context_class)
    handler.connect

    context_class.tenant_elasticsearch_prefix = nil
    handler2 = ConsoleKit::Connections::ElasticsearchConnectionHandler.new(context_class)
    handler2.connect

    expect(Thread.current[:console_kit_elasticsearch_prefix]).to be_nil
  end

  it 'sets Elasticsearch::Model.index_name_prefix when available' do
    es_model = Module.new do
      class << self
        attr_accessor :index_name_prefix
      end
    end
    stub_const('Elasticsearch::Model', es_model)

    context_class.tenant_elasticsearch_prefix = 'acme_idx'
    handler = ConsoleKit::Connections::ElasticsearchConnectionHandler.new(context_class)
    handler.connect

    expect(Elasticsearch::Model.index_name_prefix).to eq('acme_idx')
  end
end

RSpec.describe 'Dashboard integration' do
  let(:context_class) do
    Class.new do
      class << self
        attr_accessor :tenant_shard, :partner_identifier
      end
    end
  end

  before do
    stub_const('ApplicationRecord', Class.new do
      def self.establish_connection(*); end
      def self.connection; end
      def self.connection_pool; end
    end)

    ConsoleKit.configure do |config|
      config.tenants = { 'acme' => { constants: { shard: 'shard_acme', partner_code: 'ACME' } } }
      config.context_class = context_class
      config.pretty_output = false
    end
  end

  it 'renders a dashboard table for available connections' do
    pool = double(size: 5)
    conn = double(adapter_name: 'PostgreSQL', execute: true, select_value: 'PostgreSQL 14.0')
    allow(ApplicationRecord).to receive_messages(connection: conn, connection_pool: pool)

    output = capture_output { ConsoleKit::Connections::Dashboard.display }

    expect(output).to include('SQL')
    expect(output).to include('Connected')
    expect(output).to include('PostgreSQL')
  end

  it 'shows error status when connection fails' do
    allow(ApplicationRecord).to receive(:connection).and_raise(StandardError, 'timeout')
    allow(ApplicationRecord).to receive(:connection_pool).and_return(double(size: 5))

    output = capture_output { ConsoleKit::Connections::Dashboard.display }

    expect(output).to include('SQL')
    expect(output).to include('Error')
  end

  def capture_output
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
