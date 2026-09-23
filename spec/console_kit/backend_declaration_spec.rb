# frozen_string_literal: true

require 'spec_helper'

module BackendDeclaration
end

RSpec.describe BackendDeclaration do
  let(:registry) { ConsoleKit::Connections::BaseConnectionHandler }

  describe 'a handler that re-declares its backend' do
    let(:reloaded) do
      Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
        backend :declaration_alpha, display_name: 'Alpha', context_attribute: :tenant_declaration_alpha,
                                    constants_key: :declaration_alpha, detail_label: 'Alpha'
      end
    end

    before do
      reloaded.backend(:declaration_beta, display_name: 'Beta', context_attribute: :tenant_declaration_beta,
                                          constants_key: :declaration_beta, detail_label: 'Beta')
    end

    after { registry.unregister(reloaded) }

    it 'is registered exactly once' do
      expect(registry.registry.count { |klass| klass.equal?(reloaded) }).to eq(1)
    end

    it 'is registered under the key it declared last' do
      expect(registry.registry.select { |klass| klass.equal?(reloaded) }.map(&:backend_key))
        .to eq([:declaration_beta])
    end

    it 'leaves nothing behind once it is unregistered' do
      registry.unregister(reloaded)
      expect(registry.registry).not_to include(reloaded)
    end
  end

  describe 'a handler subclass that never declares a backend' do
    let(:undeclared) { Class.new(ConsoleKit::Connections::SqlConnectionHandler) }
    let(:context) do
      Class.new do
        class << self
          attr_accessor :tenant_shard
        end
      end
    end

    before { context.tenant_shard = 'shard_acme' }

    it 'inherits the backend key it specialises' do
      expect(undeclared.backend_key).to eq(:sql)
    end

    it 'inherits the constants key it specialises' do
      expect(undeclared.constants_key).to eq(:shard)
    end

    it 'resolves its parent target instead of the default' do
      expect(undeclared.new(context).target).to eq('shard_acme')
    end

    it 'is not registered, so it cannot displace the parent it borrows from' do
      expect(registry.registry).not_to include(undeclared)
    end
  end

  describe 'a handler that claims another backend context attribute' do
    def declare_shadow
      Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
        backend :shadow, display_name: 'Shadow', context_attribute: :tenant_shard,
                         constants_key: :shadow_key, detail_label: 'Shadow'
      end
    end

    it 'is refused at declaration rather than repointing the attribute' do
      expect { declare_shadow }.to raise_error(ConsoleKit::ConfigurationError, /tenant_shard/)
    end

    it 'names the backend that already owns the attribute' do
      expect { declare_shadow }.to raise_error(/:sql backend/)
    end
  end

  describe 'a handler that claims another backend constants key' do
    let(:shadow) do
      Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
        backend :shadow, display_name: 'Shadow', context_attribute: :tenant_shadow_key,
                         constants_key: :shard, detail_label: 'Shadow'
      end
    end

    let(:sql_handler) { ConsoleKit::Connections::SqlConnectionHandler.new(nil) }
    let(:targets) { ConsoleKit::TenantPlan.new('acme').targets_for([sql_handler, shadow.new(nil)]) }

    before do
      ConsoleKit.configure do |config|
        config.tenants = { 'acme' => { constants: { shard: 'shard_acme', partner_code: 'ACME' } } }
      end
      shadow
    end

    after { registry.unregister(shadow) }

    it 'cannot redirect the SQL target away from the shard constant' do
      expect(targets[:sql]).to eq('shard_acme')
    end
  end

  describe 'a blank constants value' do
    include_context 'with a four-backend tenant setup'

    { shard: '', redis_db: '  ' }.each do |key, blank|
      context "when #{key} is blank" do
        before do
          constants = TenantBackends::TENANTS['acme'][:constants].merge(key => blank)
          ConsoleKit.configuration.tenants = { 'acme' => { constants: constants } }
        end

        it 'is refused by validate!' do
          expect { ConsoleKit.configuration.validate! }.to raise_error(ConsoleKit::ConfigurationError)
        end

        it 'is refused by a tenant switch' do
          expect { ConsoleKit.switch_tenant('acme') }.to raise_error(ConsoleKit::ConfigurationError)
        end
      end
    end
  end
end
