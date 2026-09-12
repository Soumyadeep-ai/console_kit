# frozen_string_literal: true

require 'spec_helper'

# A TenantState is documented immutable, and its undo bundle is the only thing
# that can put the process back after a switch. The bundle is reachable from
# anywhere the state is - `ConsoleKit::StateStore.current` is public - so a
# console session, an application hook or a later switch could otherwise empty
# the per-backend snapshot map and leave the rollback with nothing to restore.
RSpec.describe ConsoleKit::TenantState do
  include_context 'with a four-backend tenant setup'

  describe 'the undo bundle of a committed switch' do
    let(:undo) { ConsoleKit::StateStore.current.undo }

    before { ConsoleKit.switch_tenant('acme') }

    it 'is frozen' do
      expect(undo).to be_frozen
    end

    it 'freezes the per-backend snapshot map' do
      expect(undo[:backends]).to be_frozen
    end

    it 'freezes the captured context values' do
      expect(undo[:context]).to be_frozen
    end

    it 'freezes the list of backends the switch could not drive' do
      expect(undo[:dropped]).to be_frozen
    end

    it 'freezes every handler snapshot inside the map' do
      expect(undo[:backends].values).to all(be_frozen)
    end

    it 'refuses a write into a published snapshot' do
      expect { ConsoleKit::StateStore.current.snapshot_for(:sql)[:shard] = 'shard_globex' }
        .to raise_error(FrozenError)
    end
  end

  # The tenant map belongs to the application, so a state that deep-freezes what
  # it commits has to commit a copy: freezing the configured entry in place made
  # the next `ConsoleKit.configure` or config reload raise FrozenError.
  describe 'the constants a committed switch carries' do
    let(:configured) { { shard: 'shard_acme', partner_code: 'ACME', redis_db: 2 } }
    let(:state) { ConsoleKit::StateStore.current }

    before do
      ConsoleKit.configuration.tenants = { 'acme' => { constants: configured } }
      ConsoleKit.switch_tenant('acme')
    end

    it 'leaves the configured tenant entry unfrozen' do
      expect(configured).not_to be_frozen
    end

    it 'lets a later reconfigure rewrite that entry' do
      expect { configured[:redis_db] = 9 }.not_to raise_error
    end

    it 'freezes the copy it committed' do
      expect(state.constants).to be_frozen
    end

    it 'does not share that copy with the configuration' do
      expect(state.constants).not_to equal(configured)
    end

    it 'keeps the committed target even after the configuration is rewritten' do
      configured[:redis_db] = 9
      expect(state.constants[:redis_db]).to eq(2)
    end
  end

  describe 'a tenant whose constants carry a nested container' do
    let(:routes) { { 'primary' => 'shard_acme' } }
    let(:state) { ConsoleKit::StateStore.current }

    before do
      ConsoleKit.configuration.tenants = {
        'nested' => { constants: { shard: 'shard_acme', partner_code: 'NST', routes: routes } }
      }
      ConsoleKit.switch_tenant('nested')
    end

    it 'leaves the configured container writable' do
      expect { routes['primary'] = 'shard_globex' }.not_to raise_error
    end

    it 'freezes the nested container it committed' do
      expect(state.constants[:routes]).to be_frozen
    end

    it 'cannot have its committed target changed through the configuration' do
      routes['primary'] = 'shard_globex'
      expect(state.constants[:routes]['primary']).to eq('shard_acme')
    end
  end
end
