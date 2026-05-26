# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Steps::PromptApplier do
  subject(:step) { described_class.new(ctx) }

  let(:config) { ConsoleKit.configuration }
  let(:ctx)    { ConsoleKit::PipelineContext.new(config: config) }

  before { ctx.resolved_tenant = :tenant_a }

  it 'returns success' do
    allow(ConsoleKit::Prompt).to receive(:apply)
    expect(step.call.success?).to be true
  end

  it 'calls Prompt.apply' do
    allow(ConsoleKit::Prompt).to receive(:apply)
    step.call
    expect(ConsoleKit::Prompt).to have_received(:apply)
  end
end
