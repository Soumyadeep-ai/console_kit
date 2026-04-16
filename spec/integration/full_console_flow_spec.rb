# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Full Console Flow' do
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
      config.show_dashboard = true
    end

    # Reset thread local state
    ConsoleKit::Setup.current_tenant = nil
    Thread.current[:console_kit_elasticsearch_prefix] = nil

    # Mock all external dependencies
    allow(ApplicationRecord).to receive(:establish_connection)
    allow(ApplicationRecord).to receive_messages(connection_pool: double(disconnect!: true, size: 5),
                                                 connection: double(
                                                   adapter_name: 'PostgreSQL', execute: true, select_value: '14.0'
                                                 ))

    allow(Mongoid).to receive(:override_database)
    mongo_db = instance_double(Mongoid::Database, name: 'acme_db', command: [{ 'version' => '6.0' }])
    mongo_client = instance_double(Mongoid::Client)
    allow(mongo_client).to receive(:use).with(any_args).and_return(mongo_client)
    allow(mongo_client).to receive(:database).and_return(mongo_db)

    allow(Mongoid).to receive(:default_client).and_return(mongo_client)

    allow(Redis).to receive_messages(respond_to?: true, current: instance_double(Redis, select: true, ping: 'PONG',
                                                                                        info: { 'redis_version' => '7.0', 'used_memory_human' => '1MB' }))

    allow(Elasticsearch::Model).to receive(:index_name_prefix=)
    allow(Elasticsearch::Model).to receive_messages(respond_to?: true,
                                                    client: double(
                                                      ping: true, cluster: double(health: { 'cluster_name' => 'test',
                                                                                            'status' => 'green' })
                                                    ))

    # Mock user input for TenantSelector
    allow($stdin).to receive(:gets).and_return('1')
  end

  it 'simulates a complete user journey in the console' do
    output = capture_all_output do
      # 1. Initial Setup (Simulates console start)
      ConsoleKit::Setup.setup

      # Verify first tenant (acme) is selected and configured
      expect(ConsoleKit::Setup.current_tenant).to eq('acme')
      expect(context_class.partner_identifier).to eq('ACME')
      expect(context_class.tenant_shard).to eq('shard_acme')

      # 2. Verify dashboard was shown (since config.show_dashboard = true)
      expect(ConsoleKit::Setup.current_tenant).to eq('acme')

      # 3. Simulate switching to globex
      allow($stdin).to receive(:gets).and_return('2')
      ConsoleKit::Setup.reset_current_tenant

      # Verify globex is now active
      expect(ConsoleKit::Setup.current_tenant).to eq('globex')
      expect(context_class.partner_identifier).to eq('GBX')
      expect(context_class.tenant_shard).to eq('shard_globex')

      # 4. Verify helper methods availability
      # In a real console, these are mixed into top-level
      helper_target = Object.new.extend(ConsoleKit::ConsoleHelpers)

      expect(helper_target.tenant_info).to be_nil # Prints to output
    end

    # Verify key output messages were emitted
    expect(output).to include('Tenant initialized: acme')
    expect(output).to include('Connection Dashboard')
    expect(output).to include('SQL')
    expect(output).to include('MongoDB')
    expect(output).to include('Redis')
    expect(output).to include('Elasticsearch')
    expect(output).to include('Resetting tenant: acme')
    expect(output).to include('Tenant initialized: globex')
    expect(output).to include('Tenant: globex')
    expect(output).to include('GBX')
  end

  it 'handles "none" selection correctly' do
    allow($stdin).to receive(:gets).and_return('0')

    output = capture_all_output do
      ConsoleKit::Setup.setup
    end

    expect(ConsoleKit::Setup.current_tenant).to be_nil
    expect(output).to include('No tenant selected')
    expect(context_class.partner_identifier).to be_nil
  end

  it 'handles abort/exit correctly' do
    allow($stdin).to receive(:gets).and_return('exit')
    allow(Kernel).to receive(:exit)

    capture_all_output do
      ConsoleKit::Setup.setup
    end

    expect(Kernel).to have_received(:exit)
  end

  def capture_all_output
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
    $stdout.string + $stderr.string
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end
end
