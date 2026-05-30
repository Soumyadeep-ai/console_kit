# spec/console_kit/doctor/checks/context_class_resolvable_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::Checks::ContextClassResolvable do
  subject(:check) { described_class.new(config) }

  let(:config) { ConsoleKit.configuration }

  context 'when context_class resolves to a valid constant' do
    before { config.context_class = 'Object' }

    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end

    it 'returns resolves message' do
      expect(check.call.message).to eq('context_class resolves')
    end
  end

  context 'when context_class cannot be resolved' do
    before { config.context_class = 'NonExistentClass::ThatDoesNotExist' }

    it 'returns error status' do
      expect(check.call.status).to eq(:error)
    end

    it 'includes the class name in the message' do
      expect(check.call.message).to include('NonExistentClass::ThatDoesNotExist')
    end
  end
end
