# frozen_string_literal: true

require 'spec_helper'

# The counter and event names ConsoleKit emits are a public contract:
# applications build dashboards and alerts on them, so a rename or a deletion is
# a breaking change. Every behavioural example in the suite passes with any of
# these names changed, which is why each emitting path is pinned here by name.
#
# The rollback names - console_kit.rollback and console_kit.rollback_failure -
# are pinned in rollback_integrity_spec.rb instead, alongside the unwind
# scenarios that raise them.

# A handler that satisfies the transactional contract and then fails
# verification, so a switch reaches the verification-failure path with nothing
# stubbed out of the switch itself. Deliberately not a BaseConnectionHandler
# subclass, so it can never join the registry.
class UnverifiableProbeHandler
  class << self
    def context_attribute = nil
    def constants_key = nil
  end

  attr_reader :backend_key, :display_name

  def initialize
    @backend_key = :unverifiable
    @display_name = 'Unverifiable'
  end

  def available? = true
  def prepare(_target) = nil
  def snapshot = {}
  def connect!(_target) = nil
  def restore(_state) = nil

  def verify!(_target)
    raise ConsoleKit::ConnectionVerificationError.new(nil, backend: display_name, expected: 'acme', actual: 'other')
  end
end

RSpec.describe ConsoleKit::Instrumentation do
  def count(name) = described_class.counts[name]

  describe 'a tenant switch that completes' do
    include_context 'with a four-backend tenant setup'

    before { ConsoleKit.switch_tenant('acme') }

    it 'emits console_kit.tenant_switch' do
      expect(count('console_kit.tenant_switch')).to eq(1)
    end
  end

  describe 'a switch whose backend fails verification' do
    include_context 'with a four-backend tenant setup'

    before do
      allow(ConsoleKit::Connections::ConnectionManager)
        .to receive(:available_handlers).and_return([UnverifiableProbeHandler.new])
      failed_switch('acme')
    end

    it 'emits console_kit.verification_failure' do
      expect(count('console_kit.verification_failure')).to eq(1)
    end
  end

  describe 'a registered handler that turns out to be half-implemented' do
    # Broken the way a half-implemented backend is: it inherits #available?,
    # which raises NotImplementedError. It is handed to the manager through a
    # stubbed registry rather than declared, so the count cannot be disturbed by
    # whatever else the suite has registered.
    let(:ghost_handler) do
      Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
        class << self
          def backend_key = :counter_ghost
        end
      end
    end

    before do
      allow(ConsoleKit::Output).to receive(:print_warning)
      allow(ConsoleKit::Connections::BaseConnectionHandler).to receive(:registry).and_return([ghost_handler])
      ConsoleKit::Connections::ConnectionManager.available_handlers(Class.new)
    end

    it 'emits console_kit.handler_dropped' do
      expect(count('console_kit.handler_dropped')).to eq(1)
    end
  end

  describe 'two differently named handler classes claiming one backend key' do
    let(:first) { declare_handler('FirstCollidingHandler') }
    let(:second) { declare_handler('SecondCollidingHandler') }

    def declare_handler(name)
      klass = stub_const(name, Class.new(ConsoleKit::Connections::BaseConnectionHandler))
      klass.backend(:collision_counter_key, display_name: name, context_attribute: :tenant_collision_counter,
                                            constants_key: :collision_counter, detail_label: name)
      klass
    end

    before do
      allow(ConsoleKit::Output).to receive(:print_warning)
      first
      second
    end

    after { ConsoleKit::Connections::HandlerRegistry.remove(second) }

    it 'emits console_kit.handler_collision' do
      expect(count('console_kit.handler_collision')).to eq(1)
    end
  end
end
