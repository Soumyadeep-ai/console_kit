# spec/console_kit/scoped_switcher_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::ScopedSwitcher do
  let(:config) { ConsoleKit.configuration }

  before do
    ConsoleKit.configure do |c|
      c.tenants = { tenant_a: { constants: { shard: 's', partner_code: 'p' } },
                    tenant_b: { constants: { shard: 's2', partner_code: 'p2' } } }
      c.context_class = 'Object'
      c.use_rails_sharding = false
    end
    allow(ConsoleKit::SwitchPipeline).to receive(:run).and_return(
      ConsoleKit::SwitchPipeline::Result.new(success: true, tenant: :tenant_a)
    )
  end

  describe '.for' do
    it 'returns DefaultScopedSwitcher when sharding disabled' do
      config.use_rails_sharding = false
      expect(described_class.for(config)).to be_a(ConsoleKit::DefaultScopedSwitcher)
    end

    context 'when sharding is enabled and available' do
      let(:sharded_strategy) do
        instance_double(ConsoleKit::Connections::RailsConnectedToStrategy, available?: true)
      end

      before do
        config.use_rails_sharding = true
        allow(ConsoleKit::Connections::ShardStrategyFactory).to receive(:build).and_return(sharded_strategy)
      end

      it 'returns ShardedScopedSwitcher' do
        expect(described_class.for(config)).to be_a(ConsoleKit::ShardedScopedSwitcher)
      end
    end
  end

  describe ConsoleKit::DefaultScopedSwitcher do
    subject(:switcher) { described_class.new(config) }

    it 'yields block' do
      result = nil
      switcher.with(:tenant_a) { result = :yielded }
      expect(result).to eq(:yielded)
    end

    it 'restores previous tenant after block' do
      ConsoleKit::Context.push(:tenant_b)
      switcher.with(:tenant_a) { :noop }
      expect(ConsoleKit::Context.current.tenant).to eq(:tenant_b)
    end

    context 'when the block raises an exception' do
      before { ConsoleKit::Context.push(:tenant_b) }

      it 're-raises the exception' do
        expect { switcher.with(:tenant_a) { raise 'boom' } }.to raise_error('boom')
      end

      it 'restores previous tenant after exception' do
        switcher.with(:tenant_a) { raise 'boom' } rescue nil # rubocop:disable Style/RescueModifier
        expect(ConsoleKit::Context.current.tenant).to eq(:tenant_b)
      end
    end

    it 'runs pipeline for previous tenant when popping' do
      ConsoleKit::Context.push(:tenant_b)
      switcher.with(:tenant_a) { :noop }
      expect(ConsoleKit::SwitchPipeline).to have_received(:run).at_least(:twice)
    end
  end

  describe ConsoleKit::ShardedScopedSwitcher do
    subject(:switcher) { described_class.new(config, shard_strategy) }

    let(:shard_strategy) do
      instance_double(
        ConsoleKit::Connections::RailsConnectedToStrategy,
        available?: true
      )
    end
    let(:shard_resolver) { instance_double(ConsoleKit::Connections::ShardResolver, resolve: :shard_one) }

    before do
      allow(ConsoleKit::Connections::ShardResolver).to receive(:new).and_return(shard_resolver)
      allow(shard_strategy).to receive(:wrap) do |_shard, **_opts, &block|
        block.call
      end
    end

    it 'yields the block' do
      result = nil
      switcher.with(:tenant_a) { result = :sharded }
      expect(result).to eq(:sharded)
    end

    it 'wraps block in strategy with shard and role' do
      switcher.with(:tenant_a) { :noop }
      expect(shard_strategy).to have_received(:wrap).with(:shard_one, role: config.shard_role)
    end

    it 'restores previous tenant after block' do
      ConsoleKit::Context.push(:tenant_b)
      switcher.with(:tenant_a) { :noop }
      expect(ConsoleKit::Context.current.tenant).to eq(:tenant_b)
    end

    it 're-raises exceptions from the block' do
      expect { switcher.with(:tenant_a) { raise 'shard_boom' } }.to raise_error('shard_boom')
    end

    it 'restores previous tenant after exception' do
      ConsoleKit::Context.push(:tenant_b)
      switcher.with(:tenant_a) { raise 'boom' } rescue nil # rubocop:disable Style/RescueModifier
      expect(ConsoleKit::Context.current.tenant).to eq(:tenant_b)
    end

    it 'resolves shard for the tenant key' do
      switcher.with(:tenant_a) { :noop }
      expect(shard_resolver).to have_received(:resolve).with(:tenant_a)
    end
  end
end
