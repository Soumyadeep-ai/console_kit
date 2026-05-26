# spec/console_kit/pipeline_context_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::PipelineContext do
  subject(:ctx) { described_class.new(config: ConsoleKit.configuration) }

  it 'defaults resolved_tenant to nil' do
    expect(ctx.resolved_tenant).to be_nil
  end

  it 'defaults skip_selector to false' do
    expect(ctx.skip_selector).to be false
  end

  it 'defaults scoped to false' do
    expect(ctx.scoped).to be false
  end

  it 'allows setting resolved_tenant' do
    ctx.resolved_tenant = :tenant_a
    expect(ctx.resolved_tenant).to eq(:tenant_a)
  end
end
