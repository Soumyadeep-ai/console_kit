# frozen_string_literal: true

require_relative '../../support/shared_contexts/tenant_backends'

# The Open-Closed proof.
#
# Before 1.5.0, adding a backend meant editing four files that had nothing to do
# with it: the context-attribute map, the constants map, the configuration
# validator and the console detail labels. This spec adds a fifth, fictional
# backend HERE, in the spec suite, touching no production file at all, and then
# asserts it is a first-class citizen of every one of those mechanisms.
#
# If any example here needs a production edit to pass, the refactor regressed.
RSpec.describe ConsoleKit::Connections::HandlerRegistry do
  # A complete backend, declared the way a real one is.
  let(:vault_handler) do
    Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
      backend :vault,
              display_name: 'Vault',
              context_attribute: :tenant_vault_path,
              constants_key: :vault_path,
              detail_label: 'Vault Path'

      class << self
        def store = @store ||= { path: nil }

        # This backend's one rule. `prepare` raises on it and
        # `configuration.validate!` collects it, with no second definition.
        def target_error(value)
          return if value.nil? || value.to_s.start_with?('secret/')

          'must begin with secret/'
        end
      end

      def available? = true
      def snapshot = { path: self.class.store[:path] }

      def prepare(target)
        reason = self.class.target_error(target)
        raise ConsoleKit::ConfigurationError, "Vault path #{target.inspect} #{reason}" if reason
      end

      def connect!(target) = self.class.store[:path] = target

      def verify!(target)
        actual = self.class.store[:path]
        raise verification_error(target, actual) unless actual == target
      end

      def restore(state) = self.class.store[:path] = state[:path]

      def diagnostics(level: :basic)
        { name: display_name, status: :connected, latency_ms: nil,
          details: { path: self.class.store[:path], level: level } }
      end
    end
  end

  let(:context_class) do
    Class.new do
      class << self
        attr_accessor :partner_identifier, :tenant_shard, :tenant_mongo_db,
                      :tenant_redis_db, :tenant_elasticsearch_prefix, :tenant_vault_path,
                      :tenant_doomed_key
      end
    end
  end

  let(:base_class) { TenantBackends.sharded_base }
  let(:vault_path) { 'secret/acme' }
  let(:tenants) do
    { 'acme' => { constants: TenantBackends::TENANTS['acme'][:constants].merge(vault_path: vault_path) } }
  end

  before do
    vault_handler # declaring the class registers it
    ConsoleKit.configure do |config|
      config.tenants = tenants
      config.context_class = context_class
      config.pretty_output = false
    end
    stub_const('ApplicationRecord', base_class)
    stub_const('Mongoid', TenantBackends::ThreadedMongoid)
    Redis.current = TenantBackends::CountingRedis.new
    ConsoleKit::Output.silent = true
  end

  after do
    ConsoleKit::Connections::BaseConnectionHandler.unregister(vault_handler)
    TenantBackends.reset!
  end

  describe '1. discovery' do
    it 'includes the new backend in the handlers a switch will drive' do
      keys = ConsoleKit::Connections::ConnectionManager.available_handlers(context_class).map(&:backend_key)
      expect(keys).to include(:vault)
    end
  end

  describe '2. target resolution' do
    before { ConsoleKit.switch_tenant('acme') }

    it 'resolves the target from the tenant constants key the handler declared' do
      expect(context_class.tenant_vault_path).to eq(vault_path)
    end
  end

  describe '3. connect and verify' do
    before { ConsoleKit.switch_tenant('acme') }

    it 'applies the tenant to the new backend' do
      expect(vault_handler.store[:path]).to eq(vault_path)
    end

    it 'passes verification as part of the switch' do
      expect { ConsoleKit.verify_tenant! }.not_to raise_error
    end

    it 'commits the tenant' do
      expect(ConsoleKit.current_tenant).to eq('acme')
    end
  end

  describe '4. rollback when a later backend fails' do
    # A second fictional backend, declared AFTER the first so the registry
    # applies it later. Nothing is stubbed: the failure is a real handler
    # raising from its own connect!.
    # Built lazily, so it only joins the registry inside this group.
    def doomed_handler
      @doomed_handler ||= Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
        backend :doomed, display_name: 'Doomed', context_attribute: :tenant_doomed_key,
                         constants_key: :doomed_key, detail_label: 'Doomed Key'
        def available? = true
        def snapshot = {}
        def restore(_state) = nil
        def connect!(_target) = raise(ConsoleKit::ConnectionError.new('doomed', backend: 'Doomed'))
      end
    end

    attr_reader :switch_error

    before do
      doomed_handler
      begin
        ConsoleKit.switch_tenant('acme')
      rescue ConsoleKit::TenantSwitchError => e
        @switch_error = e
      end
    end

    after { ConsoleKit::Connections::BaseConnectionHandler.unregister(doomed_handler) }

    it 'restores the earlier new backend along with every other one' do
      expect(vault_handler.store[:path]).to be_nil
    end

    it 'leaves no tenant committed' do
      expect(ConsoleKit.current_tenant).to be_nil
    end

    it 'names the failing backend without ConsoleKit knowing it exists' do
      expect(switch_error.backend).to eq('Doomed')
    end

    it 'reports that rollback succeeded' do
      expect(switch_error).to be_rollback_succeeded
    end
  end

  describe '5. configuration validation' do
    let(:vault_path) { 'wrong/acme' }

    it 'rejects a value the new backend calls invalid, using the handler rule' do
      expect { ConsoleKit.configuration.validate! }.to raise_error(ConsoleKit::Error, /vault_path/)
    end

    it 'quotes the handler own reason rather than a re-derived one' do
      expect { ConsoleKit.configuration.validate! }.to raise_error(ConsoleKit::Error, /must begin with secret/)
    end
  end

  describe '6. console tenant_info' do
    def helper = @helper ||= Class.new { include ConsoleKit::ConsoleHelpers }.new

    before do
      ConsoleKit.switch_tenant('acme')
      allow(ConsoleKit::Output).to receive(:print_info)
      ConsoleKit::Output.silent = false
      helper.tenant_info
    end

    it 'shows the new backend under the label the handler declared' do
      expect(ConsoleKit::Output).to have_received(:print_info).with(a_string_including('Vault Path'))
    end
  end

  describe '7. diagnostics' do
    before { ConsoleKit.switch_tenant('acme') }

    it 'reports the new backend in the dashboard rows' do
      names = ConsoleKit::Diagnostics.run(level: :basic).map { |row| row[:name] }
      expect(names).to include('Vault')
    end
  end

  # A Zeitwerk reload declares the handler class a second time, and the new
  # generation replaces the old one in the registry. The reloader then discards
  # the previous constant, which unregisters generation N - that must not take
  # generation N+1 with it. Reload-only, so no CI run ever reaches it.
  describe 'unregistering a generation a reload has already replaced' do
    # Built lazily, so it only joins the registry inside this group.
    def reloaded_vault
      @reloaded_vault ||= Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
        backend :vault, display_name: 'Vault', context_attribute: :tenant_vault_path,
                        constants_key: :vault_path, detail_label: 'Vault Path'
      end
    end

    before do
      reloaded_vault
      ConsoleKit::Connections::BaseConnectionHandler.unregister(vault_handler)
    end

    after { ConsoleKit::Connections::BaseConnectionHandler.unregister(reloaded_vault) }

    it 'still has a handler for the backend key' do
      keys = ConsoleKit::Connections::BaseConnectionHandler.registry.map(&:backend_key)
      expect(keys).to include(:vault)
    end

    it 'keeps the generation that replaced it' do
      expect(ConsoleKit::Connections::BaseConnectionHandler.registry).to include(reloaded_vault)
    end
  end

  # Every switch reads `.all` and iterates it. The answer is a frozen array, and
  # a different array on every call, so a caller cannot hold on to the one the
  # next switch will use nor change what that switch drives.
  describe '.all' do
    it 'hands back a frozen array' do
      expect(described_class.all).to be_frozen
    end

    it 'hands back a new array on every call, never one shared alias' do
      expect(described_class.all).not_to equal(described_class.all)
    end
  end

  describe 'registry hygiene' do
    it 'removes the fictional backend again, so it cannot leak into other examples' do
      ConsoleKit::Connections::BaseConnectionHandler.unregister(vault_handler)
      keys = ConsoleKit::Connections::BaseConnectionHandler.registry.map(&:backend_key)
      expect(keys).not_to include(:vault)
    end
  end
end
