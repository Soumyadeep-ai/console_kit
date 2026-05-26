# spec/console_kit/connections/shard_strategy_spec.rb
# frozen_string_literal: true

require 'spec_helper'

module ConsoleKit
  module Connections
    RSpec.describe NullShardStrategy do
      subject(:strategy) { described_class.new }

      it 'reports not available' do
        expect(strategy.available?).to be false
      end

      it 'yields block without wrapping' do
        result = strategy.wrap(:any_shard, role: :writing) { 42 }
        expect(result).to eq(42)
      end
    end

    RSpec.describe RailsConnectedToStrategy do
      subject(:strategy) { described_class.new }

      it 'is available when ActiveRecord responds to connected_to' do
        stub_const('ActiveRecord::Base', Class.new { def self.connected_to(**) = yield })
        stub_const('Rails::VERSION::MAJOR', 6)
        expect(strategy.available?).to be true
      end

      it 'is unavailable when ActiveRecord missing' do
        hide_const('ActiveRecord') if defined?(ActiveRecord)
        expect(strategy.available?).to be false
      end
    end
  end
end
