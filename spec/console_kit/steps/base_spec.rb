# spec/console_kit/steps/base_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Steps::Base do
  subject(:step) { described_class.new(ctx) }

  let(:config) { ConsoleKit.configuration }
  let(:ctx)    { ConsoleKit::PipelineContext.new(config: config) }

  it 'raises NotImplementedError when call is not implemented' do
    expect { step.call }.to raise_error(NotImplementedError, /Base#call not implemented/)
  end

  describe ConsoleKit::Steps::Base::Result do
    it 'reports success? true when success is true' do
      result = described_class.new(success: true)
      expect(result.success?).to be true
    end

    it 'reports failure? true when success is false' do
      result = described_class.new(success: false)
      expect(result.failure?).to be true
    end
  end
end
