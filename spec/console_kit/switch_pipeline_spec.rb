# spec/console_kit/switch_pipeline_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::SwitchPipeline do
  let(:passing_step) do
    Class.new(ConsoleKit::Steps::Base) do
      def call = success
    end
  end

  let(:failing_step) do
    Class.new(ConsoleKit::Steps::Base) do
      def call = failure('step failed')
    end
  end

  let(:config) { ConsoleKit.configuration }

  before do
    allow(config).to receive(:pipeline_steps).and_return([passing_step])
  end

  describe '.run' do
    it 'returns a Result with success true when all steps pass' do
      result = described_class.run(config: config)
      expect(result.success?).to be true
    end

    it 'returns a Result with success false when a step fails' do
      allow(config).to receive(:pipeline_steps).and_return([failing_step])
      result = described_class.run(config: config)
      expect(result.success?).to be false
    end

    it 'includes error message in result when step fails' do
      allow(config).to receive(:pipeline_steps).and_return([failing_step])
      result = described_class.run(config: config)
      expect(result.error).to eq('step failed')
    end

    context 'when config.benchmark is true' do
      before { config.benchmark = true }

      it 'outputs timing report after successful run' do
        allow(config).to receive(:pipeline_steps).and_return([passing_step])
        expect { described_class.run(config: config) }.to output(/ms/).to_stdout
      end
    end

    context 'when an early step fails' do
      let(:calls) { [] }

      let(:ordered_steps) do
        recorder = calls
        step_a = Class.new(ConsoleKit::Steps::Base) do
          define_method(:call) do
            recorder << :a
            failure('a failed')
          end
        end
        step_b = Class.new(ConsoleKit::Steps::Base) do
          define_method(:call) do
            recorder << :b
            success
          end
        end
        [step_a, step_b]
      end

      before do
        allow(config).to receive(:pipeline_steps).and_return(ordered_steps)
        described_class.run(config: config)
      end

      it 'halts at first failing step without invoking later steps' do
        expect(calls).to eq([:a])
      end
    end
  end
end
