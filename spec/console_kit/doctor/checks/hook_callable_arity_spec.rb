# spec/console_kit/doctor/checks/hook_callable_arity_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::Checks::HookCallableArity do
  subject(:check) { described_class.new(config) }

  let(:config) { ConsoleKit.configuration }

  context 'when no hooks are registered' do
    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end

    it 'returns valid message' do
      expect(check.call.message).to eq('hook arities valid')
    end
  end

  context 'when hooks have valid arity of 1' do
    before { config.before_switch { |_tenant| :ok } }

    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end
  end

  context 'when hooks have valid arity of -1 (splat)' do
    before { config.after_switch { |*_args| :ok } }

    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end
  end

  context 'when a hook has invalid arity of 0' do
    before { config.before_switch { :ok } }

    it 'returns warn status' do
      expect(check.call.status).to eq(:warn)
    end

    it 'includes arity info in the message' do
      expect(check.call.message).to include('before_switch hook arity 0')
    end
  end

  context 'when a hook has invalid arity of 2' do
    before { config.after_switch { |_a, _b| :ok } }

    it 'returns warn status' do
      expect(check.call.status).to eq(:warn)
    end

    it 'includes arity info in the message' do
      expect(check.call.message).to include('after_switch hook arity 2')
    end
  end
end
