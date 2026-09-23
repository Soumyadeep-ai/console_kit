# frozen_string_literal: true

require 'spec_helper'

module DroppedBackend
end

RSpec.describe DroppedBackend do
  include_context 'with a four-backend tenant setup'

  let(:ghost_handler) do
    Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
      backend :ghost, display_name: 'Ghost', context_attribute: :tenant_ghost_key,
                      constants_key: :ghost_key, detail_label: 'Ghost Key'
    end
  end

  let(:absent_handler) do
    Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
      backend :absent, display_name: 'Absent', context_attribute: :tenant_absent_key,
                       constants_key: :absent_key, detail_label: 'Absent Key'

      def available? = false
    end
  end

  let(:state) { ConsoleKit::StateStore.current }

  before { allow(ConsoleKit::Output).to receive(:print_warning) }

  describe 'a backend whose handler is broken' do
    before do
      ghost_handler
      ConsoleKit.switch_tenant('acme')
    end

    after { ConsoleKit::Connections::BaseConnectionHandler.unregister(ghost_handler) }

    it 'records the dropped backend on the committed state' do
      expect(state.dropped_backends).to eq([:ghost])
    end

    it 'still commits the tenant it could apply' do
      expect(ConsoleKit.current_tenant).to eq('acme')
    end

    it 'still applies the healthy backends' do
      expect(identities).to eq(expected_identities('acme'))
    end

    it 'still returns the verified state from verify_tenant!' do
      expect(ConsoleKit.verify_tenant!.tenant_key).to eq('acme')
    end

    it 'surfaces the dropped backend on the state verify_tenant! returns' do
      expect(ConsoleKit.verify_tenant!.dropped_backends).to eq([:ghost])
    end

    it 'names the dropped backend in a warning rather than reporting clean' do
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('ghost'))
    end

    it 'says the tenant is only partly verified' do
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('verified only for'))
    end

    it 'warns again on every verification, because the backend is still adrift' do
      2.times { ConsoleKit.verify_tenant! }
      expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('ghost')).twice
    end

    it 'counts the incomplete verification' do
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Instrumentation.counts['console_kit.incomplete_verification']).to eq(1)
    end
  end

  describe 'an optional gem whose handler is simply not loaded' do
    before do
      absent_handler
      ConsoleKit.switch_tenant('acme')
    end

    after { ConsoleKit::Connections::BaseConnectionHandler.unregister(absent_handler) }

    it 'is not recorded as dropped' do
      expect(state.dropped_backends).to be_empty
    end

    it 'is never named in a warning' do
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Output).not_to have_received(:print_warning).with(a_string_including('absent'))
    end
  end

  describe 'a backend that breaks after a clean switch' do
    let(:fragile_handler) do
      Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
        backend :fragile, display_name: 'Fragile', context_attribute: :tenant_fragile_key,
                          constants_key: :fragile_key, detail_label: 'Fragile Key'

        class << self
          attr_accessor :broken
        end

        def available?
          raise NotImplementedError, 'Fragile#available? is half-implemented' if self.class.broken

          true
        end

        def snapshot = {}
        def connect!(_target) = nil
        def verify!(_target) = nil
        def restore(_snapshot) = nil
      end
    end

    before do
      fragile_handler
      ConsoleKit.switch_tenant('acme')
      fragile_handler.broken = true
    end

    after { ConsoleKit::Connections::BaseConnectionHandler.unregister(fragile_handler) }

    it 'was not dropped at switch time' do
      expect(state.dropped_backends).to be_empty
    end

    it 'names the backend it could not verify' do
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('fragile'))
    end

    it 'says the tenant is only partly verified' do
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('verified only for'))
    end

    it 'counts the incomplete verification' do
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Instrumentation.counts['console_kit.incomplete_verification']).to eq(1)
    end
  end

  describe 'a sql_base_class that is configured but cannot be resolved' do
    before do
      ConsoleKit.configuration.sql_base_class = 'Legacy::NotARealRecord'
      ConsoleKit.switch_tenant('acme')
    end

    it 'records SQL as a dropped backend' do
      expect(state.dropped_backends).to eq([:sql])
    end

    it 'names the class that could not be resolved' do
      expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('Legacy::NotARealRecord'))
    end

    it 'says the tenant is only partly verified' do
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('verified only for'))
    end

    it 'still applies the backends it can drive' do
      expect(identities[:redis]).to eq(2)
    end
  end

  describe 'the default sql_base_class in an application that has no ActiveRecord' do
    before do
      hide_const('ApplicationRecord')
      ConsoleKit.switch_tenant('acme')
    end

    it 'is not recorded as dropped, because the default is allowed to be absent' do
      expect(state.dropped_backends).to be_empty
    end

    it 'is never named in a warning' do
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Output).not_to have_received(:print_warning).with(a_string_including('ApplicationRecord'))
    end
  end

  describe 'a switch with every backend healthy' do
    before { ConsoleKit.switch_tenant('acme') }

    it 'records no dropped backend' do
      expect(ConsoleKit.verify_tenant!.dropped_backends).to be_empty
    end

    it 'reports nothing extra' do
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Output).not_to have_received(:print_warning).with(a_string_including('verified only for'))
    end
  end

  describe 'a backend whose dependency is unloaded after a clean switch' do
    let(:unloaded_handler) do
      Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
        backend :unloaded, display_name: 'Unloaded', context_attribute: :tenant_unloaded_key,
                           constants_key: :unloaded_key, detail_label: 'Unloaded Key'

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
      unloaded_handler
      ConsoleKit.switch_tenant('acme')
      unloaded_handler.gone = true
    end

    after { ConsoleKit::Connections::BaseConnectionHandler.unregister(unloaded_handler) }

    it 'was not dropped at switch time' do
      expect(state.dropped_backends).to be_empty
    end

    it 'names the backend the verification could not reach' do
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('unloaded'))
    end

    it 'says the tenant is only partly verified' do
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('verified only for'))
    end

    it 'counts the incomplete verification' do
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Instrumentation.counts['console_kit.incomplete_verification']).to eq(1)
    end

    it 'still returns the verified state' do
      expect(ConsoleKit.verify_tenant!.tenant_key).to eq('acme')
    end
  end

  describe 'an optional gem that was absent before the switch as well' do
    before do
      absent_handler
      ConsoleKit.switch_tenant('acme')
    end

    after { ConsoleKit::Connections::BaseConnectionHandler.unregister(absent_handler) }

    it 'reports nothing on verification' do
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Output).not_to have_received(:print_warning).with(a_string_including('verified only for'))
    end
  end
end
