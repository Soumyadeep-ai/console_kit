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

  it 'allows setting and reading config' do
    new_config = ConsoleKit::Configuration.new
    ctx.config = new_config
    expect(ctx.config).to eq(new_config)
  end

  it 'allows setting and reading scoped' do
    ctx.scoped = true
    expect(ctx.scoped).to be true
  end

  it 'allows reading shard_strategy' do
    expect(ctx.shard_strategy).to be_nil
  end

  it 'allows setting shard_strategy' do
    strategy = instance_double(ConsoleKit::Connections::NullShardStrategy)
    ctx.shard_strategy = strategy
    expect(ctx.shard_strategy).to eq(strategy)
  end

  it 'allows reading resolved_shard' do
    expect(ctx.resolved_shard).to be_nil
  end

  it 'allows setting resolved_shard' do
    ctx.resolved_shard = :shard_one
    expect(ctx.resolved_shard).to eq(:shard_one)
  end

  it 'defaults shard_active to false' do
    expect(ctx.shard_active).to be false
  end

  it 'allows setting shard_active' do
    ctx.shard_active = true
    expect(ctx.shard_active).to be true
  end

  it 'sets skip_selector to true when requested_tenant is provided' do
    ctx_with_tenant = described_class.new(config: ConsoleKit.configuration, requested_tenant: :t1)
    expect(ctx_with_tenant.skip_selector).to be true
  end

  it 'sets resolved_tenant from requested_tenant' do
    ctx_with_tenant = described_class.new(config: ConsoleKit.configuration, requested_tenant: :t1)
    expect(ctx_with_tenant.resolved_tenant).to eq(:t1)
  end
end
