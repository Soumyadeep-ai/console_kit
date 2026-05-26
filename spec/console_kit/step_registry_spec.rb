# spec/console_kit/step_registry_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::StepRegistry do
  let(:step_a) { Class.new { def self.priority = 10 } }
  let(:step_b) { Class.new { def self.priority = 20 } }

  after { described_class.send(:registry).clear }

  describe '.register' do
    it 'adds step to registry' do
      described_class.register(step_a, priority: 10)
      expect(described_class.ordered).to include(step_a)
    end
  end

  describe '.ordered' do
    it 'returns steps sorted by priority ascending' do
      described_class.register(step_b, priority: 20)
      described_class.register(step_a, priority: 10)
      expect(described_class.ordered.first).to eq(step_a)
    end
  end

  describe '.insert_before' do
    let(:step_c) { Class.new }

    before do
      described_class.register(step_b, priority: 20)
      described_class.insert_before(step_b, step_c, priority: 15)
    end

    it 'inserts new step before target' do
      expect(described_class.ordered.index(step_c)).to be < described_class.ordered.index(step_b)
    end
  end

  describe '.remove' do
    it 'removes step from registry' do
      described_class.register(step_a, priority: 10)
      described_class.remove(step_a)
      expect(described_class.ordered).not_to include(step_a)
    end
  end
end
