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

    it 're-raises the exception' do
      ConsoleKit::Context.push(:tenant_b)
      expect { switcher.with(:tenant_a) { raise 'boom' } }.to raise_error('boom')
    end

    context 'when block raises with previous tenant active' do
      before do
        ConsoleKit::Context.push(:tenant_b)
        switcher.with(:tenant_a) { raise 'boom' }
      rescue RuntimeError
        nil
      end

      it 'restores previous tenant after exception' do
        expect(ConsoleKit::Context.current.tenant).to eq(:tenant_b)
      end
    end

    it 'runs pipeline for previous tenant when popping' do
      ConsoleKit::Context.push(:tenant_b)
      switcher.with(:tenant_a) { :noop }
      expect(ConsoleKit::SwitchPipeline).to have_received(:run).at_least(:twice)
    end

    context 'when the pipeline fails' do
      let(:block_yield_result) do
        yielded = false
        begin
          switcher.with(:tenant_a) { yielded = true }
        rescue ConsoleKit::Error
          nil
        end
        yielded
      end

      before do
        allow(ConsoleKit::SwitchPipeline).to receive(:run).and_return(
          ConsoleKit::SwitchPipeline::Result.new(success: false, error: 'unknown tenant')
        )
      end

      it 'raises ConsoleKit::Error' do
        expect { switcher.with(:tenant_a) { :noop } }.to raise_error(ConsoleKit::Error, 'unknown tenant')
      end

      it 'does not yield the block' do
        expect(block_yield_result).to be(false)
      end
    end

    context 'when pipeline fails with previous tenant active' do
      before do
        allow(ConsoleKit::SwitchPipeline).to receive(:run).and_return(
          ConsoleKit::SwitchPipeline::Result.new(success: false, error: 'unknown tenant')
        )
        ConsoleKit::Context.push(:tenant_b)
        begin
          switcher.with(:tenant_a) { :noop }
        rescue ConsoleKit::Error
          nil
        end
      end

      it 'restores context by popping the pushed tenant' do
        expect(ConsoleKit::Context.current.tenant).to eq(:tenant_b)
      end
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

    context 'when previous tenant active and block raises' do
      before do
        ConsoleKit::Context.push(:tenant_b)
        switcher.with(:tenant_a) { raise 'boom' }
      rescue RuntimeError
        nil
      end

      it 'restores previous tenant after exception' do
        expect(ConsoleKit::Context.current.tenant).to eq(:tenant_b)
      end
    end

    it 'resolves shard for the tenant key' do
      switcher.with(:tenant_a) { :noop }
      expect(shard_resolver).to have_received(:resolve).with(:tenant_a)
    end

    context 'when the pipeline fails' do
      let(:block_yield_result) do
        yielded = false
        begin
          switcher.with(:tenant_a) { yielded = true }
        rescue ConsoleKit::Error
          nil
        end
        yielded
      end

      before do
        allow(ConsoleKit::SwitchPipeline).to receive(:run).and_return(
          ConsoleKit::SwitchPipeline::Result.new(success: false, error: 'unknown shard tenant')
        )
      end

      it 'raises ConsoleKit::Error' do
        expect { switcher.with(:tenant_a) { :noop } }.to raise_error(ConsoleKit::Error, 'unknown shard tenant')
      end

      it 'does not yield the block' do
        expect(block_yield_result).to be(false)
      end
    end

    context 'when pipeline fails with previous tenant active' do
      before do
        allow(ConsoleKit::SwitchPipeline).to receive(:run).and_return(
          ConsoleKit::SwitchPipeline::Result.new(success: false, error: 'unknown shard tenant')
        )
        ConsoleKit::Context.push(:tenant_b)
        begin
          switcher.with(:tenant_a) { :noop }
        rescue ConsoleKit::Error
          nil
        end
      end

      it 'restores context by popping the pushed tenant' do
        expect(ConsoleKit::Context.current.tenant).to eq(:tenant_b)
      end
    end

    it 'runs restore pipeline outside shard wrapper' do
      ConsoleKit::Context.push(:tenant_b)
      switcher.with(:tenant_a) { :noop }
      expect(shard_strategy).to have_received(:wrap).once
    end
  end
end
