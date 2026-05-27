# spec/console_kit/step_registry_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::StepRegistry do
  let(:step_a) { Class.new { def self.priority = 10 } }
  let(:step_b) { Class.new { def self.priority = 20 } }
  let(:step_c) { Class.new }

  around do |example|
    saved = described_class.send(:registry).dup
    described_class.send(:registry).clear
    example.run
  ensure
    described_class.send(:registry).replace(saved)
  end

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
    before do
      described_class.register(step_b, priority: 20)
      described_class.insert_before(step_b, described_class::Entry.new(klass: step_c, priority: 15))
    end

    it 'inserts new step before target' do
      expect(described_class.ordered.index(step_c)).to be < described_class.ordered.index(step_b)
    end

    it 'falls back to entry priority when target not found' do
      step_d = Class.new
      step_missing = Class.new
      described_class.insert_before(step_missing, described_class::Entry.new(klass: step_d, priority: 99))
      expect(described_class.ordered).to include(step_d)
    end
  end

  describe '.insert_after' do
    before do
      described_class.register(step_a, priority: 10)
    end

    it 'inserts new step after target' do
      described_class.insert_after(step_a, described_class::Entry.new(klass: step_c, priority: 5))
      expect(described_class.ordered.index(step_a)).to be < described_class.ordered.index(step_c)
    end

    it 'falls back to entry priority when target not found' do
      step_missing = Class.new
      step_d = Class.new
      described_class.insert_after(step_missing, described_class::Entry.new(klass: step_d, priority: 1))
      expect(described_class.ordered).to include(step_d)
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
