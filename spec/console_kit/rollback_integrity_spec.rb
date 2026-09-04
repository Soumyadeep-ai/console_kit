# frozen_string_literal: true

require 'spec_helper'

# An unwind decides what to put back from the snapshot it captured, never from
# whatever happens to be available when the scope closes. A backend whose
# handler has disappeared in between - a reload that undefined a gem constant, a
# reconfigured base class, an `available?` that fails transiently - is still
# serving the inner tenant, so it has to be reported rather than quietly counted
# as restored.
module RollbackIntegrity
end

RSpec.describe RollbackIntegrity do
  include_context 'with a four-backend tenant setup'

  let(:live_handlers) { ConsoleKit::Connections::ConnectionManager.available_handlers(context_class) }
  let(:without_redis) { live_handlers.reject { |handler| handler.backend_key == :redis } }
  let(:error) { closed_scope_error }

  # Every handler is present for the switch; Redis' handler is gone by the time
  # the scope closes and the unwind asks what is available.
  before do
    allow(ConsoleKit::Connections::ConnectionManager)
      .to receive(:available_handlers).and_return(live_handlers, without_redis)
  end

  def closed_scope_error
    ConsoleKit.with_tenant('acme') { :noop }
    nil
  rescue ConsoleKit::RollbackError => e
    e
  end

  def failure_backends = error.failures.map { |failure| failure[:backend] }

  describe 'a backend that was available at switch time but not at unwind time' do
    it 'raises RollbackError rather than reporting a clean unwind' do
      expect(error).to be_a(ConsoleKit::RollbackError)
    end

    it 'names the backend it could not restore' do
      expect(failure_backends).to eq([:redis])
    end

    it 'says no handler was available to restore it' do
      expect(error.failures.first[:error]).to be_a(ConsoleKit::UnsupportedBackendError)
    end

    it 'explains why the backend was abandoned' do
      expect(error.failures.first[:error].message).to include('no connection handler is available to restore it')
    end

    it 'never counts the abandoned backend as restored' do
      error
      expect(Redis.current.db_index).to eq(2)
    end

    it 'still restores the backends whose handlers survived' do
      error
      expect(identities[:sql]).to eq('default')
    end

    it 'still returns the store to the enclosing state' do
      error
      expect(ConsoleKit.current_tenant).to be_nil
    end
  end
end
