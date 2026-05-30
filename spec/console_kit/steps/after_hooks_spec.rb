# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Steps::AfterHooks do
  subject(:step) { described_class.new(ctx) }

  let(:config) { ConsoleKit.configuration }
  let(:ctx)    { ConsoleKit::PipelineContext.new(config: config) }

  before { ctx.resolved_tenant = :tenant_a }

  it 'returns success when no hooks registered' do
    expect(step.call.success?).to be true
  end

  it 'runs registered after_switch hook' do
    called = false
    config.after_switch { called = true }
    step.call
    expect(called).to be true
  end

  it 'returns failure when an abort hook raises HookError' do
    config.after_switch(on_error: :abort) { raise 'after hook failure' }
    expect(step.call.failure?).to be true
  end

  it 'includes the hook error message in the failure' do
    config.after_switch(on_error: :abort) { raise 'hook failed msg' }
    result = step.call
    expect(result.error).to include('hook failed msg')
  end
end
