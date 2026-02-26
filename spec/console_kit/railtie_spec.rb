# frozen_string_literal: true

require 'spec_helper'

# Define Rails mock globally for this spec
module Rails
  # Mock Railtie for testing
  class Railtie
    def self.config
      @config ||= begin
        c = Class.new do
          attr_accessor :to_prepare_blocks

          def initialize = @to_prepare_blocks = []
          def to_prepare(&block) = @to_prepare_blocks << block
        end
        c.new
      end
    end

    def self.console(&block) = @console_block = block
    class << self
      attr_reader :console_block
    end
  end
end

# Load the railtie
require_relative '../../lib/console_kit/railtie'

RSpec.describe ConsoleKit::Railtie do
  it 'defines Railtie' do
    expect(defined?(described_class)).to be_truthy
  end

  it 'inherits from Rails::Railtie' do
    expect(described_class).to be < Rails::Railtie
  end

  describe 'console hook' do
    it 'registers a console block' do
      expect(described_class.console_block).to be_a(Proc)
    end

    it 'calls Setup.setup when the console block is executed' do
      allow(ConsoleKit::Setup).to receive(:setup)
      described_class.console_block.call
      expect(ConsoleKit::Setup).to have_received(:setup)
    end
  end

  describe 'to_prepare hook' do
    it 'calls Setup.reapply if in a console session' do
      stub_const('Rails::Console', Class.new)
      allow(ConsoleKit::Setup).to receive(:reapply)

      # Manually trigger the to_prepare blocks
      described_class.config.to_prepare_blocks.each(&:call)

      expect(ConsoleKit::Setup).to have_received(:reapply)
    end

    it 'does not call Setup.reapply if not in a console session' do
      hide_const('Rails::Console')
      allow(ConsoleKit::Setup).to receive(:reapply)

      described_class.config.to_prepare_blocks.each(&:call)

      expect(ConsoleKit::Setup).not_to have_received(:reapply)
    end
  end
end
