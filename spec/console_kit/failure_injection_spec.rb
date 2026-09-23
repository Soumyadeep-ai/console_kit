# frozen_string_literal: true

require 'spec_helper'

# The six things that must be true after ANY failed tenant switch: the tenant
# key, the context object and all four backend identities are exactly what they
# were before the switch was attempted.
RSpec.shared_examples 'a fully rolled back switch' do
  it 'restores the previous tenant' do
    expect(ConsoleKit.current_tenant).to eq(baseline[:tenant])
  end

  it 'restores the previous context' do
    expect(context_values).to eq(baseline[:context])
  end

  it 'restores the previous SQL state' do
    expect(identities[:sql]).to eq(baseline[:identities][:sql])
  end

  it 'restores the previous Mongo state' do
    expect(identities[:mongo]).to eq(baseline[:identities][:mongo])
  end

  it 'restores the previous Redis state' do
    expect(identities[:redis]).to eq(baseline[:identities][:redis])
  end

  it 'restores the previous Elasticsearch state' do
    expect(identities[:elasticsearch]).to eq(baseline[:identities][:elasticsearch])
  end
end

# Starts on acme, records everything observable, lets the example arrange a
# failure through #arrange_failure, then attempts a switch to globex.
RSpec.shared_context 'with a failed switch away from acme' do
  let(:baseline) { observable_state }
  let(:error) { failed_switch('globex') }

  before do
    ConsoleKit.switch_tenant('acme')
    baseline
    spy_on_handlers!
    arrange_failure
    error
  end

  def arrange_failure = nil
end

# A fixed handler order, so "SQL succeeded, Mongo succeeded, then Redis failed"
# is a scenario rather than an accident of Class#descendants ordering.
module FailureInjection
  ORDER = %i[sql mongo redis elasticsearch].freeze
end

RSpec.describe FailureInjection do
  include_context 'with a four-backend tenant setup'

  let(:handlers) { ordered_handlers }

  before do
    allow(ConsoleKit::Connections::ConnectionManager).to receive(:available_handlers).and_return(handlers)
  end

  def ordered_handlers
    found = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class)
    FailureInjection::ORDER.map { |key| found.find { |handler| handler.backend_key == key } }
  end

  def handler_for(key) = handlers.find { |handler| handler.backend_key == key }

  # Installed only once the baseline switch is done, so "never connected" means
  # "not during the switch under test".
  def spy_on_handlers!
    handlers.each do |handler|
      allow(handler).to receive(:connect!).and_call_original
      allow(handler).to receive(:snapshot).and_call_original
    end
  end

  def break_connect(key, error)
    allow(handler_for(key)).to receive(:connect!).and_raise(error)
  end

  def connection_failure(backend)
    ConsoleKit::ConnectionError.new(backend: backend, tenant: 'globex', operation: :connect)
  end

  describe 'a backend that fails while connecting' do
    include_context 'with a failed switch away from acme'

    context 'when SQL fails first, before anything else has been touched' do
      def arrange_failure = break_connect(:sql, connection_failure('SQL'))

      it_behaves_like 'a fully rolled back switch'

      it 'raises TenantSwitchError' do
        expect(error).to be_a(ConsoleKit::TenantSwitchError)
      end

      it 'names the failing backend on the error' do
        expect(error.backend).to eq('SQL')
      end
    end

    context 'when MongoDB fails after SQL succeeded' do
      def arrange_failure = break_connect(:mongo, connection_failure('MongoDB'))

      it_behaves_like 'a fully rolled back switch'

      it 'reports a fully successful rollback' do
        expect(error).to be_rollback_succeeded
      end
    end

    context 'when Redis fails after SQL and MongoDB succeeded' do
      def arrange_failure = break_connect(:redis, connection_failure('Redis'))

      it_behaves_like 'a fully rolled back switch'

      it 'had really moved SQL before the failure' do
        expect(handler_for(:sql)).to have_received(:connect!)
      end

      it 'had really moved MongoDB before the failure' do
        expect(handler_for(:mongo)).to have_received(:connect!)
      end

      it 'never reached Elasticsearch' do
        expect(handler_for(:elasticsearch)).not_to have_received(:connect!)
      end
    end

    context 'when Elasticsearch fails last, after every other backend succeeded' do
      def arrange_failure = break_connect(:elasticsearch, connection_failure('Elasticsearch'))

      it_behaves_like 'a fully rolled back switch'

      it 'reports a fully successful rollback' do
        expect(error).to be_rollback_succeeded
      end
    end
  end

  describe 'a backend that fails while preparing, before any mutation' do
    include_context 'with a failed switch away from acme'

    def arrange_failure
      allow(handler_for(:redis)).to receive(:prepare)
        .and_raise(ConsoleKit::UnsupportedBackendError, 'Redis DB 3 cannot be selected')
    end

    it_behaves_like 'a fully rolled back switch'

    it 'raises the validation error itself, since there is nothing to roll back' do
      expect(error).to be_a(ConsoleKit::UnsupportedBackendError)
    end

    it 'never asks any backend to connect' do
      expect(handler_for(:sql)).not_to have_received(:connect!)
    end

    it 'never snapshots anything' do
      expect(handler_for(:mongo)).not_to have_received(:snapshot)
    end

    it 'issues no Redis SELECT' do
      expect(Redis.current.selects).to eq([2])
    end

    it 'leaves the tenant fully verifiable' do
      expect(ConsoleKit.verify_tenant!.tenant_key).to eq('acme')
    end
  end

  describe 'a connection that succeeds but points at the wrong tenant' do
    include_context 'with a failed switch away from acme'

    # Every connect! succeeds. A foreign writer moves Redis in the window
    # between the last connect and the first verify, so the switch is only
    # caught because #verify! reads the live identity back.
    def arrange_failure
      allow(handler_for(:elasticsearch)).to receive(:connect!).and_wrap_original do |original, target|
        Redis.current.select(9)
        original.call(target)
      end
    end

    it_behaves_like 'a fully rolled back switch'

    it 'fails verification rather than reporting success' do
      expect(error.original_error).to be_a(ConsoleKit::ConnectionVerificationError)
    end

    it 'reports the identity it expected' do
      expect(error.original_error.expected).to eq(3)
    end

    it 'reports the identity it actually found' do
      expect(error.original_error.actual).to eq(9)
    end

    it 'names the backend that could not be proved' do
      expect(error.backend).to eq('Redis')
    end

    it 'still connected every backend before verifying' do
      expect(handler_for(:elasticsearch)).to have_received(:connect!)
    end
  end

  describe 'a context writer that raises' do
    include_context 'with a failed switch away from acme'

    def arrange_failure
      allow(context_class).to receive(:tenant_mongo_db=).and_raise(RuntimeError, 'context writer failed')
    end

    it_behaves_like 'a fully rolled back switch'

    it 'raises TenantSwitchError' do
      expect(error).to be_a(ConsoleKit::TenantSwitchError)
    end

    it 'preserves the writer failure as the root cause' do
      expect(error.original_error.message).to eq('context writer failed')
    end

    it 'reports that the rollback did not fully succeed' do
      expect(error).not_to be_rollback_succeeded
    end

    it 'names the context as the component that could not be restored' do
      expect(error.rollback_failures.map { |failure| failure[:backend] }).to eq(['context'])
    end

    it 'never touches a backend, because the context is applied first' do
      expect(handler_for(:sql)).not_to have_received(:connect!)
    end
  end

  describe 'a context writer that rejects the tenant value' do
    include_context 'with a failed switch away from acme'

    def arrange_failure
      allow(context_class).to receive(:tenant_redis_db=).and_raise(ArgumentError, 'redis db must be a String')
    end

    it_behaves_like 'a fully rolled back switch'

    it 'preserves the rejection as the root cause' do
      expect(error.original_error).to be_a(ArgumentError)
    end
  end

  describe 'a context object that exposes only some of the attributes' do
    let(:context_class) { partial_context_class }

    before { ConsoleKit.switch_tenant('globex') }

    def partial_context_class
      Class.new do
        class << self
          attr_accessor :partner_identifier, :tenant_shard
        end
      end
    end

    it 'writes the attribute it does expose' do
      expect(context_class.tenant_shard).to eq('shard_globex')
    end

    it 'still moves the backends whose context attribute is missing' do
      expect(identities[:redis]).to eq(3)
    end

    it 'commits the switch rather than failing on the missing writers' do
      expect(ConsoleKit.current_tenant).to eq('globex')
    end
  end

  describe 'a context class that cannot be resolved at all' do
    before { ConsoleKit.configuration.context_class = 'NoSuchTenantContext' }

    it 'raises a ConfigurationError naming the class' do
      expect { ConsoleKit.switch_tenant('globex') }.to raise_error(ConsoleKit::Error, /NoSuchTenantContext/)
    end

    it 'touches no backend' do
      failed_switch('globex')
      expect(identities).to eq(expected_identities(nil))
    end

    it 'leaves the process on no tenant' do
      failed_switch('globex')
      expect(ConsoleKit.current_tenant).to be_nil
    end
  end

  describe 'a rollback that fails on top of the original failure' do
    include_context 'with a failed switch away from acme'

    def arrange_failure
      break_connect(:elasticsearch, StandardError.new('elasticsearch refused the prefix'))
      allow(handler_for(:sql)).to receive(:restore).and_raise(StandardError, 'shard registry offline')
    end

    it 'still raises TenantSwitchError, not a bare rollback error' do
      expect(error).to be_a(ConsoleKit::TenantSwitchError)
    end

    it 'keeps the original root cause rather than replacing it' do
      expect(error.original_error.message).to eq('elasticsearch refused the prefix')
    end

    it 'repeats the root cause in the message' do
      expect(error.message).to include('elasticsearch refused the prefix')
    end

    it 'reports that the rollback did not succeed' do
      expect(error).not_to be_rollback_succeeded
    end

    it 'names the backend that could not be restored' do
      expect(error.rollback_failures.map { |failure| failure[:backend] }).to eq(['SQL'])
    end

    it 'carries the rollback failure itself' do
      expect(error.rollback_failures.first[:error].message).to eq('shard registry offline')
    end

    it 'warns about the incomplete rollback in the message' do
      expect(error.message).to include('rollback did not fully succeed')
    end

    it 'still restores every backend the broken one did not own' do
      expect(identities[:elasticsearch]).to eq(baseline[:identities][:elasticsearch])
    end

    it 'still restores the context' do
      expect(context_values).to eq(baseline[:context])
    end
  end

  describe 'what a switch failure tells the operator' do
    include_context 'with a failed switch away from acme'

    def arrange_failure = break_connect(:redis, connection_failure('Redis'))

    it 'names the tenant it was leaving' do
      expect(error.message).to include('"acme"')
    end

    it 'names the tenant it was moving to' do
      expect(error.message).to include('"globex"')
    end

    it 'names the backend that failed' do
      expect(error.message).to include('Redis')
    end

    it 'names the operation that failed' do
      expect(error.message).to include('connect')
    end

    it 'says whether the previous state came back' do
      expect(error.message).to include('restored successfully')
    end

    it 'exposes the tenant it was leaving as an attribute' do
      expect(error.from_tenant).to eq('acme')
    end

    it 'exposes the tenant it was moving to as an attribute' do
      expect(error.to_tenant).to eq('globex')
    end

    it 'exposes the failing operation as an attribute' do
      expect(error.original_error.operation).to eq(:connect)
    end
  end

  describe 'a verification failure message' do
    include_context 'with a failed switch away from acme'

    def arrange_failure
      allow(handler_for(:elasticsearch)).to receive(:connect!).and_wrap_original do |original, target|
        Redis.current.select(9)
        original.call(target)
      end
    end

    it 'reports the identity it expected' do
      expect(error.message).to include('Expected 3')
    end

    it 'reports the identity it found instead' do
      expect(error.message).to include('got 9')
    end
  end

  describe 'a Redis client error, which the handler scrubs before it escapes' do
    include_context 'with a failed switch away from acme'

    def arrange_failure
      Redis.current.reachable = false
    end

    it_behaves_like 'a fully rolled back switch'

    it 'replaces the connection URL with a placeholder' do
      expect(error.message).to include('[redacted]')
    end

    it 'never leaks the password out of the client error' do
      expect(error.message).not_to include('s3cr3t')
    end

    it 'never leaks the host out of the client error' do
      expect(error.message).not_to include('cache.internal')
    end
  end

  describe 'the message ConsoleKit writes itself' do
    include_context 'with a failed switch away from acme'

    def arrange_failure = break_connect(:redis, connection_failure('Redis'))

    it 'carries no scheme-and-credentials URL of its own' do
      expect(consolekit_authored_message).not_to include('://')
    end

    it 'carries no credential assignment of its own' do
      expect(consolekit_authored_message).not_to match(/password|secret|token/i)
    end

    # Everything in the message except the backend's own root-cause text.
    def consolekit_authored_message
      error.message.sub(error.original_error.message, '')
    end
  end
end
