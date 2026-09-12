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
  end
end
