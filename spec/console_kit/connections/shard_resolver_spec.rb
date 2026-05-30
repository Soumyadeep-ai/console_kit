# spec/console_kit/connections/shard_resolver_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Connections::ShardResolver do
  subject(:resolver) { described_class.new(config) }

  let(:config) do
    ConsoleKit.configure do |c|
      c.tenants = { tenant_a: { constants: { shard: 'shard_01', partner_code: 'pa' } } }
      c.default_shard = :default
      c.context_class = 'Object'
    end
    ConsoleKit.configuration
  end

  it 'resolves shard from tenant constants' do
    expect(resolver.resolve(:tenant_a)).to eq('shard_01')
  end

  it 'returns default_shard for unknown tenant' do
    expect(resolver.resolve(:nonexistent)).to eq(:default)
  end

  context 'when the tenant has no shard key in its constants' do
    let(:other_config) do
      ConsoleKit.reset_configuration!
      ConsoleKit.configure do |c|
        c.tenants = { tenant_b: { constants: { partner_code: 'pb' } } }
        c.default_shard = :my_default
        c.context_class = 'Object'
      end
      ConsoleKit.configuration
    end

    it 'returns the configured default_shard' do
      other_resolver = described_class.new(other_config)
      expect(other_resolver.resolve(:tenant_b)).to eq(:my_default)
    end
  end
end
