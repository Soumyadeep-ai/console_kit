# frozen_string_literal: true

require 'spec_helper'

# `ConsoleKit.switch_tenant` can be called without `Configuration#validate!`
# ever having run, so the plan is the last place a malformed tenant map is
# caught - before the switch starts touching backends.
RSpec.describe ConsoleKit::TenantPlan do
  describe 'a tenant whose :constants is not a Hash' do
    before { ConsoleKit.configuration.tenants = { 'acme' => { constants: 'shard_acme' } } }

    it 'raises ConfigurationError rather than a bare NoMethodError' do
      expect { described_class.new('acme').constants }.to raise_error(ConsoleKit::ConfigurationError)
    end

    it 'names the class it was given instead' do
      expect { described_class.new('acme').constants }.to raise_error(/String/)
    end

    it 'is refused by a switch too' do
      expect { ConsoleKit.switch_tenant('acme') }.to raise_error(ConsoleKit::ConfigurationError)
    end
  end

  describe 'a tenant key that is not configured' do
    def error_for(tenants)
      ConsoleKit.configuration.tenants = tenants
      described_class.new('acme').constants
    rescue ConsoleKit::TenantNotFoundError => e
      e
    end

    it 'lists the configured tenant keys, so a typo is visible' do
      expect(error_for('acmee' => {}, globex: {}).message).to end_with('Configured tenants: "acmee", :globex.')
    end

    it 'says so when no tenants are configured at all' do
      expect(error_for({}).message).to end_with('No tenants are configured.')
    end
  end

  describe 'a tenant entry that is not a Hash' do
    before { ConsoleKit.configuration.tenants = { 'acme' => 'shard_acme' } }

    it 'raises ConfigurationError rather than a bare TypeError out of dig' do
      expect { described_class.new('acme').constants }.to raise_error(ConsoleKit::ConfigurationError)
    end
  end

  # An omitted backend key means the tenant does not name that backend, and a
  # switch RESETS it to its default. Preserving it instead would leave the
  # previous tenant's Redis live under the new tenant's SQL - the mixed-tenant
  # state every other guarantee in this release exists to prevent, and one that
  # `verify_tenant!` would then attest as fully verified.
  describe 'a tenant that omits a backend key' do
    include_context 'with a four-backend tenant setup'

    let(:sql_only) { { constants: { shard: 'shard_acme', partner_code: 'ACME' } } }

    before do
      ConsoleKit.configuration.tenants = TenantBackends::TENANTS.merge('sql_only' => sql_only)
      ConsoleKit.switch_tenant('globex')
      ConsoleKit.switch_tenant('sql_only')
    end

    it 'plans no target for the omitted backend' do
      expect(described_class.new('sql_only').targets_for(handlers)[:redis]).to be_nil
    end

    it 'switches the backend the tenant does name' do
      expect(identities[:sql]).to eq('shard_acme')
    end

    it 'resets the omitted Redis backend instead of leaving it on the previous tenant' do
      expect(identities[:redis]).to eq(0)
    end

    it 'resets the omitted Mongo backend' do
      expect(identities[:mongo]).to be_nil
    end

    it 'resets the omitted Elasticsearch backend' do
      expect(identities[:elasticsearch]).to be_nil
    end

    it 'clears the context attribute of the omitted backend' do
      expect(context_values[:tenant_redis_db]).to be_nil
    end

    def handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)
  end
end
