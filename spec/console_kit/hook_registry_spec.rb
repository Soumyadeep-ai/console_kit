# spec/console_kit/hook_registry_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::HookRegistry do
  subject(:registry) { described_class.new }

  describe '#register' do
    it 'raises ArgumentError for invalid on_error value' do
      noop = proc {}
      expect { registry.register(:before_switch, on_error: :invalid, &noop) }
        .to raise_error(ArgumentError, /on_error must be :abort or :warn/)
    end
  end

  describe '#hooks_for' do
    it 'returns an empty array for an event with no hooks' do
      expect(registry.hooks_for(:before_switch)).to eq([])
    end

    it 'returns registered hooks for an event' do
      noop = proc {}
      registry.register(:before_switch, &noop)
      expect(registry.hooks_for(:before_switch).size).to eq(1)
    end

    it 'does not return hooks for a different event' do
      noop = proc {}
      registry.register(:after_switch, &noop)
      expect(registry.hooks_for(:before_switch)).to be_empty
    end
  end

  describe '#run' do
    it 'calls registered hook with tenant' do
      received = nil
      registry.register(:before_switch) { |t| received = t }
      registry.run(:before_switch, :tenant_a)
      expect(received).to eq(:tenant_a)
    end

    it 'raises HookError when on_error :abort and hook raises' do
      registry.register(:before_switch, on_error: :abort) { raise 'boom' }
      expect { registry.run(:before_switch, :tenant_a) }
        .to raise_error(ConsoleKit::HookError, /before_switch hook failed: boom/)
    end

    it 'does not raise when on_error :warn and hook raises' do
      registry.register(:before_switch, on_error: :warn) { raise 'boom' }
      expect { registry.run(:before_switch, :tenant_a) }.not_to raise_error
    end

    context 'when first :abort hook fails' do
      let(:calls) { [] }

      before do
        registry.register(:before_switch, on_error: :abort) { raise 'first' }
        registry.register(:before_switch) { calls << :second }
      end

      it 'raises HookError' do
        expect { registry.run(:before_switch, :tenant_a) }.to raise_error(ConsoleKit::HookError)
      end

      it 'does not call subsequent hooks' do
        registry.run(:before_switch, :tenant_a)
      rescue ConsoleKit::HookError
        expect(calls).to be_empty
      end
    end

    it 'runs multiple hooks in order' do
      calls = []
      registry.register(:before_switch) { calls << :first }
      registry.register(:before_switch) { calls << :second }
      registry.run(:before_switch, :tenant_a)
      expect(calls).to eq(%i[first second])
    end

    it 'does not run hooks for different event' do
      called = false
      registry.register(:after_switch) { called = true }
      registry.run(:before_switch, :tenant_a)
      expect(called).to be false
    end
  end
end
