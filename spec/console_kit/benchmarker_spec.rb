# spec/console_kit/benchmarker_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Benchmarker do
  subject(:bm) { described_class.new }

  describe '#wrap' do
    it 'yields block and returns result' do
      result = bm.wrap('Step') { 42 }
      expect(result).to eq(42)
    end

    it 'records duration for step' do
      bm.wrap('Step') { nil }
      expect(bm.timings['Step']).to be >= 0
    end
  end

  describe '#start_memory_tracking' do
    it 'does not raise' do
      expect { bm.start_memory_tracking }.not_to raise_error
    end
  end

  describe '#report' do
    context 'with memory tracking enabled' do
      before do
        bm.start_memory_tracking
        bm.wrap('StepA') { nil }
        bm.wrap('StepB') { sleep 0.01 }
      end

      it 'outputs tenant key' do
        expect { bm.report(:tenant_a) }.to output(/tenant_a/).to_stdout
      end

      it 'outputs step name' do
        expect { bm.report(:tenant_a) }.to output(/StepA/).to_stdout
      end

      it 'outputs ms unit' do
        expect { bm.report(:tenant_a) }.to output(/ms/).to_stdout
      end

      it 'marks the slowest step' do
        expect { bm.report(:tenant_a) }.to output(/slowest/).to_stdout
      end

      it 'outputs memory delta' do
        expect { bm.report(:tenant_a) }.to output(/Allocated objects delta/).to_stdout
      end
    end

    context 'without memory tracking' do
      before { bm.wrap('StepA') { nil } }

      it 'does not output memory delta' do
        expect { bm.report(:tenant_a) }.not_to output(/Allocated objects delta/).to_stdout
      end
    end

    it 'does not raise when no steps were recorded' do
      bm.start_memory_tracking
      expect { bm.report(:tenant_a) }.to output(/Tenant switch/).to_stdout
    end
  end

  describe '#slowest_step' do
    it 'returns step with longest duration' do
      bm.wrap('Fast') { nil }
      bm.wrap('Slow') { sleep 0.01 }
      expect(bm.slowest_step.first).to eq('Slow')
    end

    it 'returns nil when no steps recorded' do
      expect(bm.slowest_step).to be_nil
    end
  end
end
