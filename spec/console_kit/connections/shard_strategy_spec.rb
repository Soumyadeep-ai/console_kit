# spec/console_kit/connections/shard_strategy_spec.rb
# frozen_string_literal: true

require 'spec_helper'

module ConsoleKit
  module Connections
    RSpec.describe ShardStrategy do
      subject(:strategy) { described_class.new }

      it 'raises NotImplementedError for available?' do
        expect { strategy.available? }.to raise_error(NotImplementedError)
      end

      it 'raises NotImplementedError for wrap' do
        expect { strategy.wrap(:shard) { nil } }.to raise_error(NotImplementedError)
      end
    end

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

      it 'is available when ActiveRecord responds to connected_to and Rails >= 6' do
        stub_const('ActiveRecord::Base', Class.new { def self.connected_to(**) = yield })
        stub_const('Rails::VERSION::MAJOR', 6)
        expect(strategy.available?).to be true
      end

      it 'is unavailable when ActiveRecord missing' do
        hide_const('ActiveRecord') if defined?(ActiveRecord)
        expect(strategy.available?).to be false
      end

      it 'is unavailable when ActiveRecord::Base does not respond to connected_to' do
        ar_base_without_connected_to = Class.new
        stub_const('ActiveRecord::Base', ar_base_without_connected_to)
        stub_const('Rails::VERSION::MAJOR', 6)
        expect(strategy.available?).to be false
      end

      context 'when Rails::VERSION::MAJOR is not defined' do
        let(:ar_base_connectable) do
          Class.new { def self.connected_to(**) = yield }
        end

        it 'is unavailable' do
          stub_const('ActiveRecord::Base', ar_base_connectable)
          hide_const('Rails::VERSION') if defined?(Rails::VERSION)
          expect(strategy.available?).to be false
        end
      end

      it 'is unavailable when Rails version is below 6' do
        stub_const('ActiveRecord::Base', Class.new { def self.connected_to(**) = yield })
        stub_const('Rails::VERSION::MAJOR', 5)
        expect(strategy.available?).to be false
      end

      context 'when connected_to is available' do
        let(:ar_base_yielding) do
          Class.new { def self.connected_to(**) = yield }
        end

        let(:ar_base_failing) do
          Class.new do
            def self.connected_to(**)
              raise ActiveRecord::ConnectionNotEstablished, 'not connected'
            end
          end
        end

        before do
          stub_const('Rails::VERSION::MAJOR', 6)
        end

        it 'wraps the block with ActiveRecord connected_to' do
          stub_const('ActiveRecord::Base', ar_base_yielding)
          result = strategy.wrap(:my_shard, role: :writing) { :connected }
          expect(result).to eq(:connected)
        end

        it 'falls back to direct block call on ConnectionNotEstablished' do
          stub_const('ActiveRecord::Base', ar_base_failing)
          stub_const('ActiveRecord::ConnectionNotEstablished', Class.new(StandardError))
          allow(ConsoleKit::Output).to receive(:print_warning)
          result = strategy.wrap(:missing_shard, role: :writing) { :fallback }
          expect(result).to eq(:fallback)
        end

        it 'prints warning on ConnectionNotEstablished fallback' do
          stub_const('ActiveRecord::Base', ar_base_failing)
          stub_const('ActiveRecord::ConnectionNotEstablished', Class.new(StandardError))
          allow(ConsoleKit::Output).to receive(:print_warning)
          strategy.wrap(:bad_shard, role: :writing) { :ok }
          expect(ConsoleKit::Output).to have_received(:print_warning).with(/bad_shard.*unavailable/)
        end
      end
    end
  end
end
