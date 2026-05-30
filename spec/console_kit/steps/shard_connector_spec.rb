# spec/console_kit/steps/shard_connector_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Steps::ShardConnector do
  subject(:step) { described_class.new(ctx) }

  let(:config) { ConsoleKit.configuration }
  let(:ctx)    { ConsoleKit::PipelineContext.new(config: config) }

  before do
    ConsoleKit.configure do |c|
      c.tenants = { tenant_a: { constants: { shard: 'shard_01', partner_code: 'pa' } } }
      c.context_class = 'Object'
    end
    ctx.resolved_tenant = :tenant_a
  end

  context 'when use_rails_sharding is false' do
    before { config.use_rails_sharding = false }

    it 'returns success without setting shard_strategy' do
      expect(step.call.success?).to be true
    end

    it 'does not set ctx.shard_strategy' do
      step.call
      expect(ctx.shard_strategy).to be_nil
    end
  end

  context 'when sharding enabled but strategy unavailable' do
    before do
      config.use_rails_sharding = true
      allow(ConsoleKit::Connections::ShardStrategyFactory)
        .to receive(:build).and_return(ConsoleKit::Connections::NullShardStrategy.new)
    end

    it 'returns success' do
      expect(step.call.success?).to be true
    end
  end

  context 'when sharding enabled and available' do
    let(:strategy) do
      instance_double(ConsoleKit::Connections::RailsConnectedToStrategy, available?: true)
    end

    before do
      config.use_rails_sharding = true
      allow(ConsoleKit::Connections::ShardStrategyFactory).to receive(:build).and_return(strategy)
    end

    it 'sets ctx.shard_strategy' do
      step.call
      expect(ctx.shard_strategy).to eq(strategy)
    end

    it 'sets ctx.resolved_shard' do
      step.call
      expect(ctx.resolved_shard).to eq('shard_01')
    end
  end
end
