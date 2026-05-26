# spec/console_kit/connections/shard_strategy_factory_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Connections::ShardStrategyFactory do
  let(:config) { ConsoleKit.configuration }

  describe '.build' do
    it 'returns NullShardStrategy when use_rails_sharding is false' do
      config.use_rails_sharding = false
      expect(described_class.build(config)).to be_a(ConsoleKit::Connections::NullShardStrategy)
    end

    it 'returns NullShardStrategy when connected_to unavailable' do
      config.use_rails_sharding = true
      unavailable_strategy = instance_double(ConsoleKit::Connections::RailsConnectedToStrategy, available?: false)
      allow(ConsoleKit::Connections::RailsConnectedToStrategy).to receive(:new).and_return(unavailable_strategy)
      expect(described_class.build(config)).to be_a(ConsoleKit::Connections::NullShardStrategy)
    end
  end
end
