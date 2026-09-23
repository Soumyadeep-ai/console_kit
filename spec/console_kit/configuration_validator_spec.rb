# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::ConfigurationValidator do
  subject(:validate!) { described_class.new(config).validate! }

  let(:config) { ConsoleKit::Configuration.new }
  let(:valid_constants) do
    { shard: :shard1, partner_code: 'acme', mongo_db: 'acme_db', redis_db: 1, elasticsearch_prefix: 'acme' }
  end
  let(:valid_tenants) { { acme: { constants: valid_constants } } }

  before do
    allow(ConsoleKit::Output).to receive(:print_warning)
    stub_const('Something', Class.new)
    config.context_class = 'Something'
  end

  def raises_configuration_error?
    yield
    false
  rescue ConsoleKit::ConfigurationError
    true
  end

  def redis_handler_rejects?(value)
    raises_configuration_error? { ConsoleKit::Connections::RedisConnectionHandler.new(nil).prepare(value) }
  end

  def es_handler_rejects?(value)
    raises_configuration_error? { ConsoleKit::Connections::ElasticsearchConnectionHandler.new(nil).prepare(value) }
  end

  it 'does not raise for a fully valid tenant map' do
    config.tenants = valid_tenants
    expect { validate! }.not_to raise_error
  end

  describe 'tenant map structure' do
    it 'raises when a tenant entry is not a Hash' do
      config.tenants = { acme: 'not-a-hash' }
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /:acme.*must be a Hash/)
    end

    it 'raises when a tenant entry has no :constants key' do
      config.tenants = { acme: {} }
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /:acme is missing a `:constants`/)
    end

    it 'raises when :constants is present but not a Hash' do
      config.tenants = { acme: { constants: 'nope' } }
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /:acme `:constants`.*Hash/)
    end
  end

  describe 'tenant identifiers' do
    it 'raises when a tenant key is neither a Symbol nor a String' do
      config.tenants = { 1 => { constants: valid_constants } }
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /identifier 1 must be/)
    end

    it 'raises when a tenant key is a blank string' do
      config.tenants = { '' => { constants: valid_constants } }
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /identifier "" must be/)
    end

    it 'catches tenant identifiers that duplicate by case' do
      config.tenants = { acme: { constants: valid_constants }, ACME: { constants: valid_constants } }
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /are duplicates once normalized/)
    end

    it 'catches tenant identifiers that duplicate by type' do
      config.tenants = { acme: { constants: valid_constants }, 'acme' => { constants: valid_constants } }
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /are duplicates once normalized/)
    end
  end

  describe 'required constants keys' do
    it 'raises naming the tenant and the missing keys' do
      config.tenants = { acme: { constants: { mongo_db: 'db' } } }
      expect { validate! }.to raise_error(
        ConsoleKit::ConfigurationError, /:acme.*missing required keys: shard, partner_code/
      )
    end

    it 'reads its required keys from TenantPlan::REQUIRED_KEYS so the two cannot drift' do
      expect(ConsoleKit::TenantPlan::REQUIRED_KEYS).to eq(%i[shard partner_code])
    end
  end

  describe 'redis_db validation' do
    it 'raises naming the tenant, the key and the bad value' do
      config.tenants = { acme: { constants: valid_constants.merge(redis_db: -1) } }
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /:acme redis_db -1 is invalid/)
    end

    it 'rejects a non-numeric string' do
      config.tenants = { acme: { constants: valid_constants.merge(redis_db: 'primary') } }
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /redis_db "primary" is invalid/)
    end

    it 'rejects a float' do
      config.tenants = { acme: { constants: valid_constants.merge(redis_db: 1.5) } }
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /redis_db 1\.5 is invalid/)
    end
  end

  describe 'elasticsearch_prefix validation' do
    it 'rejects an uppercase prefix, naming the tenant and value' do
      config.tenants = { acme: { constants: valid_constants.merge(elasticsearch_prefix: 'Acme') } }
      expect { validate! }.to raise_error(
        ConsoleKit::ConfigurationError, /:acme elasticsearch_prefix "Acme" is invalid: must be lowercase/
      )
    end

    it 'rejects a prefix with a leading underscore' do
      config.tenants = { acme: { constants: valid_constants.merge(elasticsearch_prefix: '_acme') } }
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /must not begin with/)
    end

    it 'rejects a prefix with an illegal character' do
      config.tenants = { acme: { constants: valid_constants.merge(elasticsearch_prefix: 'acme/idx') } }
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /must not contain/)
    end
  end

  describe 'mongo_db and shard validation' do
    it 'rejects a mongo_db that is not a String or Symbol' do
      config.tenants = { acme: { constants: valid_constants.merge(mongo_db: 123) } }
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /:acme mongo_db 123 is invalid/)
    end

    it 'rejects a blank mongo_db' do
      config.tenants = { acme: { constants: valid_constants.merge(mongo_db: '') } }
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /mongo_db "" is invalid/)
    end

    it 'rejects a shard that is not a String or Symbol' do
      config.tenants = { acme: { constants: valid_constants.merge(shard: 42) } }
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /:acme shard 42 is invalid/)
    end
  end

  describe 'aggregation of multiple problems' do
    let(:error_message) do
      config.tenants = {
        acme: { constants: { mongo_db: 'db' } },
        globex: { constants: valid_constants.merge(redis_db: -1) }
      }
      begin
        validate!
        nil
      rescue ConsoleKit::ConfigurationError => e
        e.message
      end
    end

    it 'reports the first tenant problem' do
      expect(error_message).to include(':acme constants missing required keys')
    end

    it 'reports the second tenant problem in the same message' do
      expect(error_message).to include(':globex redis_db -1 is invalid')
    end
  end

  describe 'context_class resolvability' do
    it 'raises when context_class cannot be resolved, alongside a valid tenant map' do
      config.tenants = valid_tenants
      config.context_class = 'DoesNotExistAtAll'
      expect { validate! }.to raise_error(ConsoleKit::ConfigurationError, /could not be found/)
    end
  end

  describe 'warnings (do not raise)' do
    it 'does not raise about unrecognised constants keys' do
      config.tenants = { acme: { constants: valid_constants.merge(redis_dbs: 3) } }
      expect { validate! }.not_to raise_error
    end

    it 'prints the unrecognised constants key warning' do
      config.tenants = { acme: { constants: valid_constants.merge(redis_dbs: 3) } }
      validate!
      expect(ConsoleKit::Output).to have_received(:print_warning).with(/unrecognised keys: :redis_dbs/)
    end

    it 'does not raise when the context class is missing writers' do
      stub_const('BareContext', Class.new)
      config.tenants = valid_tenants
      config.context_class = 'BareContext'
      expect { validate! }.not_to raise_error
    end

    it 'prints the missing-writer warning naming the missing attributes' do
      stub_const('BareContext', Class.new)
      config.tenants = valid_tenants
      config.context_class = 'BareContext'
      validate!
      expect(ConsoleKit::Output).to have_received(:print_warning).with(/no writer for:.*partner_identifier/)
    end

    it 'ignores unrecognised top-level tenant keys the host app carries' do
      config.tenants = { acme: { constants: valid_constants, label: 'Acme Inc' } }
      validate!
      expect(ConsoleKit::Output).not_to have_received(:print_warning).with(/unrecognised keys: :label/)
    end

    it 'does not warn about writers for backends no tenant names' do
      stub_const('ShardOnlyContext', Class.new { class << self; attr_accessor :partner_identifier, :tenant_shard; end })
      config.tenants = { acme: { constants: { partner_code: 'acme', shard: :acme } } }
      config.context_class = 'ShardOnlyContext'
      validate!
      expect(ConsoleKit::Output).not_to have_received(:print_warning).with(/no writer for/)
    end

    it 'does not call the :environment constants key a possible typo' do
      config.tenants = { acme: { constants: valid_constants.merge(environment: 'production') } }
      validate!
      expect(ConsoleKit::Output).not_to have_received(:print_warning).with(/unrecognised keys: :environment/)
    end
  end

  describe 'a context class whose writers live on the singleton' do
    let(:singleton_context) do
      Class.new do
        class << self
          attr_accessor :partner_identifier, :tenant_shard, :tenant_mongo_db,
                        :tenant_redis_db, :tenant_elasticsearch_prefix
        end
      end
    end

    before do
      stub_const('SingletonContext', singleton_context)
      config.context_class = 'SingletonContext'
      config.tenants = valid_tenants
    end

    it 'does not warn that a backend will never be configured' do
      validate!
      expect(ConsoleKit::Output).not_to have_received(:print_warning).with(/no writer for/)
    end
  end

  describe 'a context class that can carry every backend' do
    let(:full_context) do
      Class.new do
        attr_writer :partner_identifier, :tenant_shard, :tenant_mongo_db,
                    :tenant_redis_db, :tenant_elasticsearch_prefix
      end
    end

    before do
      stub_const('FullContext', full_context)
      config.context_class = 'FullContext'
      config.tenants = valid_tenants
    end

    it 'warns about nothing' do
      validate!
      expect(ConsoleKit::Output).not_to have_received(:print_warning)
    end
  end

  describe 'a tenant that configures only the backends it uses' do
    before { config.tenants = { acme: { constants: { shard: :shard1, partner_code: 'acme' } } } }

    it 'validates a SQL-only tenant without error' do
      expect { validate! }.not_to raise_error
    end

    it 'says nothing about resets, because no other tenant names more' do
      validate!
      expect(ConsoleKit::Output).not_to have_received(:print_warning).with(/RESETS/)
    end
  end

  describe 'a tenant map where only some tenants name a backend' do
    before do
      config.tenants = { acme: { constants: valid_constants },
                         beta: { constants: { shard: :shard2, partner_code: 'beta' } } }
    end

    it 'does not raise, because naming fewer backends is legitimate' do
      expect { validate! }.not_to raise_error
    end

    it 'warns that a switch to the shorter tenant resets what it omits' do
      validate!
      expect(ConsoleKit::Output).to have_received(:print_warning).with(/RESETS/)
    end

    it 'names the backend keys it will reset' do
      validate!
      expect(ConsoleKit::Output).to have_received(:print_warning).with(/:redis_db/)
    end
  end

  describe 'credential scrubbing' do
    let(:credential_url) { 'redis://user:hunter2@cache.internal:6379/1' }
    let(:error_message) do
      config.tenants = { acme: { constants: valid_constants.merge(redis_db: credential_url) } }
      begin
        validate!
        ''
      rescue ConsoleKit::ConfigurationError => e
        e.message
      end
    end

    it 'scrubs a credential-bearing URI echoed in an invalid redis_db message' do
      expect(error_message).not_to include('hunter2')
    end
  end

  describe 'Redis DB rule parity with RedisConnectionHandler' do
    redis_values = [0, 5, '3', '0', nil, -1, 1.5, 2.0, 'primary', '-1'].freeze

    redis_values.each do |value|
      it "agrees with the handler on #{value.inspect}" do
        config.tenants = { acme: { constants: valid_constants.merge(redis_db: value) } }

        expect(raises_configuration_error? { validate! }).to eq(redis_handler_rejects?(value))
      end
    end
  end

  describe 'Elasticsearch prefix rule parity with ElasticsearchConnectionHandler' do
    es_values = ['', nil, 'acme', 'Acme', 'acme idx', '_acme', '-acme', 'acme/idx', 'acme#idx'].freeze

    es_values.each do |value|
      it "agrees with the handler on #{value.inspect}" do
        config.tenants = { acme: { constants: valid_constants.merge(elasticsearch_prefix: value) } }

        expect(raises_configuration_error? { validate! }).to eq(es_handler_rejects?(value))
      end
    end
  end
end
