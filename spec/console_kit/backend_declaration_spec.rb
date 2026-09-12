# frozen_string_literal: true

require 'spec_helper'

# A handler is meant to be the single source of truth for its backend: its
# `backend` declaration is the only place the backend is named, and its
# `.target_error` is the only rule that decides whether a target value is
# usable. These examples pin the places where that ownership used to leak -
# a second declaration leaving the first key registered, a subclass that never
# declared one, another handler hijacking the constants key, and a target value
# that `validate!` and a live switch judged differently.
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

  # Class-level instance variables are not inherited, so a subclass that only
  # adds behaviour used to have a nil key, a nil context attribute and a nil
  # constants key - a handler for no backend at all, whose `#connect` reset its
  # parent's backend to the default without a word.
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

  # `context_mapping` is a merged map keyed by context attribute, so a handler
  # declaring another backend's context attribute silently repoints it. The
  # handler already knows its own constants key; nothing else gets a vote.
  describe 'a handler that claims another backend context attribute' do
    let(:shadow) do
      Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
        backend :shadow, display_name: 'Shadow', context_attribute: :tenant_shard,
                         constants_key: :shadow_key, detail_label: 'Shadow'
      end
    end

    let(:sql_handler) { ConsoleKit::Connections::SqlConnectionHandler.new(nil) }
    let(:targets) { ConsoleKit::TenantPlan.new('acme').targets_for([sql_handler]) }

    before do
      ConsoleKit.configure do |config|
        config.tenants = { 'acme' => { constants: { shard: 'shard_acme', partner_code: 'ACME',
                                                    shadow_key: 'hijacked' } } }
      end
      shadow
    end

    after { registry.unregister(shadow) }

    it 'cannot redirect the SQL target away from the shard constant' do
      expect(targets[:sql]).to eq('shard_acme')
    end
  end

  # `target_error` exists so the validator and the switch cannot disagree. They
  # disagreed anyway: the switch stripped a blank constant to nil before asking,
  # so a configuration `validate!` refused outright was switched to happily -
  # onto the default shard and the default Redis DB.
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
