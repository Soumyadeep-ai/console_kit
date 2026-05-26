# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Steps::BeforeHooks do
  subject(:step) { described_class.new(ctx) }

  let(:config) { ConsoleKit.configuration }
  let(:ctx)    { ConsoleKit::PipelineContext.new(config: config) }

  before { ctx.resolved_tenant = :tenant_a }

  it 'returns success when no hooks registered' do
    expect(step.call.success?).to be true
  end

  it 'runs registered before_switch hook' do
    called = false
    config.before_switch { called = true }
    step.call
    expect(called).to be true
  end

  it 'returns failure when hook raises with on_error :abort' do
    config.before_switch(on_error: :abort) { raise 'nope' }
    expect(step.call.failure?).to be true
  end
end
