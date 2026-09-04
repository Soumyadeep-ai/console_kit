# frozen_string_literal: true

RSpec.describe ConsoleKit::TenantSwitch do
  # A handler that satisfies the contract without inheriting BaseConnectionHandler,
  # so it can never leak into the descendants-based registry.
  let(:handler_class) do
    Class.new do
      class << self
        attr_accessor :context_attribute_name
      end

      attr_reader :identity, :restored, :backend_key

      def initialize(backend_key, failure: nil)
        @backend_key = backend_key
        @failure = failure
        @identity = nil
      end

      def display_name = @backend_key.to_s.upcase
      def available? = true
      def prepare(_target) = nil
      def snapshot = { identity: @identity }
      def verify!(_target) = nil

      def connect!(target)
        raise @failure if @failure

        @identity = target
      end

      def restore(snapshot)
        @restored = true
        @identity = snapshot[:identity]
      end
    end
  end

  let(:context_class) do
    Class.new do
      class << self
        attr_accessor :partner_identifier, :tenant_shard, :tenant_mongo_db,
                      :tenant_redis_db, :tenant_elasticsearch_prefix
      end
    end
  end

  let(:healthy) { build_handler(:sql, :tenant_shard) }
  let(:broken) { build_handler(:mongo, :tenant_mongo_db, failure: NotImplementedError.new('no connect!')) }

  def build_handler(key, attribute, failure: nil)
    klass = Class.new(handler_class)
    klass.context_attribute_name = attribute
    klass.new(key, failure: failure)
  end

  before do
    ConsoleKit.configure do |config|
      config.context_class = context_class
      config.tenants = {
        acme: { constants: { partner_code: 'ACME', shard: 'shard_acme', mongo_db: 'acme_db' } },
        globex: { constants: { partner_code: 'GLOBEX', shard: 'shard_globex', mongo_db: 'globex_db' } }
      }
    end
    allow(ConsoleKit::Connections::ConnectionManager).to receive(:available_handlers).and_return([healthy, broken])
  end

  describe 'a handler that does not implement the contract' do
    # NotImplementedError descends from ScriptError, not StandardError, so a
    # partially implemented handler used to escape the transaction entirely and
    # leave the process half-switched.
    subject(:switch) { ConsoleKit::Output.silence { described_class.call(:acme) } }

    it 'raises TenantSwitchError rather than letting the raw error escape' do
      expect { switch }.to raise_error(ConsoleKit::TenantSwitchError)
    end

    it 'preserves the root cause' do
      switch
    rescue ConsoleKit::TenantSwitchError => e
      expect(e.original_error).to be_a(NotImplementedError)
    end

    it 'reports that rollback succeeded' do
      switch
    rescue ConsoleKit::TenantSwitchError => e
      expect(e).to be_rollback_succeeded
    end

    it 'rolls the already-connected backend back' do
      switch
    rescue ConsoleKit::TenantSwitchError
      expect(healthy.identity).to be_nil
    end

    it 'restores the context' do
      switch
    rescue ConsoleKit::TenantSwitchError
      expect(context_class.tenant_shard).to be_nil
    end

    it 'leaves no tenant marked as current' do
      switch
    rescue ConsoleKit::TenantSwitchError
      expect(ConsoleKit::StateStore.tenant_key).to be_nil
    end

    # The handler raised a bare NotImplementedError and never wrapped it, so the
    # only thing that knows which backend was being applied is the coordinator.
    it 'attributes the raw failure to the backend that raised it' do
      switch
    rescue ConsoleKit::TenantSwitchError => e
      expect(e.backend).to eq('MONGO')
    end

    it 'names that backend in the headline' do
      switch
    rescue ConsoleKit::TenantSwitchError => e
      expect(e.message).to include('(MONGO)')
    end
  end

  describe 'a handler that wrapped its own failure' do
    subject(:switch) { ConsoleKit::Output.silence { described_class.call(:acme) } }

    let(:wrapped) { ConsoleKit::ConnectionError.new(backend: 'Redis', tenant: 'acme', operation: :connect) }

    before { allow(broken).to receive(:connect!).and_raise(wrapped) }

    it 'keeps the backend the handler named rather than the one being applied' do
      switch
    rescue ConsoleKit::TenantSwitchError => e
      expect(e.backend).to eq('Redis')
    end
  end

  describe 'rollback that itself fails' do
    subject(:switch) { ConsoleKit::Output.silence { described_class.call(:acme) } }

    before do
      allow(healthy).to receive(:restore).and_raise(IOError, 'socket gone')
    end

    it 'still reports the original failure as the root cause' do
      switch
    rescue ConsoleKit::TenantSwitchError => e
      expect(e.original_error).to be_a(NotImplementedError)
    end

    it 'reports that rollback did not succeed' do
      switch
    rescue ConsoleKit::TenantSwitchError => e
      expect(e).not_to be_rollback_succeeded
    end

    it 'names the backend that could not be rolled back' do
      switch
    rescue ConsoleKit::TenantSwitchError => e
      expect(e.rollback_failures.map { |f| f[:backend] }).to include('SQL')
    end

    it 'mentions the rollback failure in the message' do
      switch
    rescue ConsoleKit::TenantSwitchError => e
      expect(e.message).to include('rollback did not fully succeed')
    end
  end

  describe 'a snapshot that fails before anything is applied' do
    subject(:switch) { ConsoleKit::Output.silence { described_class.call(:acme) } }

    before { allow(healthy).to receive(:snapshot).and_raise(ArgumentError, 'snapshot boom') }

    it 'raises TenantSwitchError rather than a NoMethodError from the rollback path' do
      expect { switch }.to raise_error(ConsoleKit::TenantSwitchError)
    end

    it 'preserves the root cause instead of replacing it with a rollback error' do
      switch
    rescue ConsoleKit::TenantSwitchError => e
      expect(e.original_error).to be_a(ArgumentError)
    end

    it 'leaves the context untouched, because nothing was applied' do
      switch
    rescue ConsoleKit::TenantSwitchError
      expect(context_class.tenant_shard).to be_nil
    end

    it 'never connects a backend' do
      switch
    rescue ConsoleKit::TenantSwitchError
      expect(healthy.identity).to be_nil
    end
  end

  describe 'a root cause carrying credentials' do
    subject(:switch) { ConsoleKit::Output.silence { described_class.call(:acme) } }

    let(:uri) { 'postgres://deploy:sup3rs3cret@db.internal:5432/acme' }

    before { allow(broken).to receive(:connect!).and_raise(RuntimeError, "auth failed for #{uri}") }

    it 'does not echo the password into the switch error' do
      switch
    rescue ConsoleKit::TenantSwitchError => e
      expect(e.message).not_to include('sup3rs3cret')
    end

    it 'does not echo the credential-bearing URI into the switch error' do
      switch
    rescue ConsoleKit::TenantSwitchError => e
      expect(e.message).not_to include(uri)
    end

    it 'still reports that the switch failed' do
      switch
    rescue ConsoleKit::TenantSwitchError => e
      expect(e.message).to include('Failed to switch tenant')
    end
  end

  describe 'a context writer that fails during rollback' do
    subject(:switch) { ConsoleKit::Output.silence { described_class.call(:acme) } }

    let(:context_class) do
      Class.new do
        class << self
          attr_accessor :tenant_shard, :tenant_mongo_db, :tenant_redis_db, :tenant_elasticsearch_prefix
          attr_reader :partner_identifier

          def partner_identifier=(value)
            raise IOError, 'partner writer offline' if value.nil?

            @partner_identifier = value
          end
        end
      end
    end

    it 'still restores the attributes it could write' do
      switch
    rescue ConsoleKit::TenantSwitchError
      expect(context_class.tenant_shard).to be_nil
    end

    it 'reports that rollback did not fully succeed' do
      switch
    rescue ConsoleKit::TenantSwitchError => e
      expect(e).not_to be_rollback_succeeded
    end

    it 'names the attributes left on the tenant the switch failed to reach' do
      switch
    rescue ConsoleKit::TenantSwitchError => e
      expect(e.message).to include('partner_identifier')
    end
  end
end
