# frozen_string_literal: true

require 'spec_helper'

module RollbackIntegrity
end

class RollbackProbeHandler
  PREVIOUS = 'previous'

  class << self
    def context_attribute = nil
    def constants_key = nil
  end

  attr_reader :backend_key, :display_name, :identity

  def initialize(backend_key, restore_error: nil)
    @backend_key = backend_key
    @display_name = backend_key.to_s.upcase
    @restore_error = restore_error
    @identity = PREVIOUS
  end

  def available? = true
  def prepare(_target) = nil
  def snapshot = { identity: @identity }
  def verify!(_target) = nil
  def connect!(target) = @identity = target

  def restore(state)
    raise @restore_error if @restore_error

    @identity = state[:identity]
  end
end

RSpec.describe RollbackIntegrity do
  include_context 'with a four-backend tenant setup'

  let(:error) { closed_scope_error }

  def closed_scope_error
    ConsoleKit.with_tenant('acme') { :noop }
    nil
  rescue ConsoleKit::RollbackError => e
    e
  end

  def failure_backends = error.failures.map { |failure| failure[:backend] }

  def stub_handlers(handlers)
    allow(ConsoleKit::Connections::ConnectionManager).to receive(:available_handlers).and_return(handlers)
  end

  describe 'a backend that was available at switch time but not at unwind time' do
    let(:live_handlers) { ConsoleKit::Connections::ConnectionManager.available_handlers(context_class) }
    let(:without_redis) { live_handlers.reject { |handler| handler.backend_key == :redis } }

    before do
      allow(ConsoleKit::Connections::ConnectionManager)
        .to receive(:available_handlers).and_return(live_handlers, without_redis)
    end

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

    it 'counts the backend it had to abandon' do
      error
      expect(ConsoleKit::Instrumentation.counts['console_kit.rollback_failure']).to eq(1)
    end
  end

  describe 'an unwind in which two backends fail to restore' do
    let(:survivor) { RollbackProbeHandler.new(:alpha) }
    let(:handlers) do
      [survivor,
       RollbackProbeHandler.new(:boom_one, restore_error: IOError.new('boom_one socket gone')),
       RollbackProbeHandler.new(:boom_two, restore_error: IOError.new('boom_two socket gone'))]
    end

    before do
      stub_handlers(handlers)
      error
    end

    it 'collects a failure for every backend that raised, not only the first' do
      expect(error.failures.size).to eq(2)
    end

    it 'names both of them, newest-applied first' do
      expect(failure_backends).to eq(%w[BOOM_TWO BOOM_ONE])
    end

    it 'still puts back a backend ordered after the ones that raised' do
      expect(survivor.identity).to eq(RollbackProbeHandler::PREVIOUS)
    end

    it 'counts one rollback failure per backend it could not put back' do
      expect(ConsoleKit::Instrumentation.counts['console_kit.rollback_failure']).to eq(2)
    end

    it 'counts the unwind itself' do
      expect(ConsoleKit::Instrumentation.counts['console_kit.rollback']).to eq(1)
    end
  end

  describe 'the order the backends are put back in' do
    let(:restore_order) { [] }
    let(:handlers) { ConsoleKit::Connections::ConnectionManager.available_handlers(context_class) }

    before do
      handlers.each { |handler| record_restores(handler, restore_order) }
      stub_handlers(handlers)
      ConsoleKit.with_tenant('acme') { :noop }
    end

    def record_restores(handler, log)
      allow(handler).to receive(:restore).and_wrap_original do |original, *args|
        log << handler.backend_key
        original.call(*args)
      end
    end

    it 'is the exact reverse of the order they were applied in' do
      expect(restore_order).to eq(handlers.map(&:backend_key).reverse)
    end
  end

  describe 'the context slot of a backend whose handler vanished mid-scope' do
    let(:context_class) do
      Class.new do
        class << self
          attr_accessor :partner_identifier, :tenant_shard, :tenant_mongo_db, :tenant_redis_db,
                        :tenant_elasticsearch_prefix, :tenant_probe_key
        end
      end
    end

    let(:applied_inside) { [] }

    let(:probe_handler) do
      Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
        backend :probe, display_name: 'Probe', context_attribute: :tenant_probe_key,
                        constants_key: :probe_key, detail_label: 'Probe Key'

        class << self
          attr_accessor :gone
        end

        def available? = !self.class.gone
        def snapshot = {}
        def connect!(_target) = nil
        def verify!(_target) = nil
        def restore(_snapshot) = nil
      end
    end

    before do
      probe_handler
      ConsoleKit.configuration.tenants = probe_tenants
      vanish_mid_scope
    end

    after { ConsoleKit::Connections::BaseConnectionHandler.unregister(probe_handler) }

    def probe_tenants
      TenantBackends::TENANTS.transform_values do |tenant|
        { constants: tenant[:constants].merge(probe_key: "#{tenant[:constants][:partner_code]}_probe") }
      end
    end

    def vanish_mid_scope
      ConsoleKit.with_tenant('acme') do
        applied_inside << context_class.tenant_probe_key
        probe_handler.gone = true
      end
    rescue ConsoleKit::RollbackError
      nil
    end

    it 'had applied the slot on the way in' do
      expect(applied_inside).to eq(['ACME_probe'])
    end

    it 'writes the captured value back into the slot' do
      expect(context_class.tenant_probe_key).to be_nil
    end

    it 'restores the slots whose handlers survived as well' do
      expect(context_class.tenant_shard).to be_nil
    end
  end
end
