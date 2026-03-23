# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ConsoleKit::Railtie' do
  before do
    # Mock Rails and Railtie
    stub_const('Rails', Module.new)
    stub_const('Rails::Railtie', Class.new do
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

      def self.console(&block)
        @console_block = block
      end

      class << self
        attr_reader :console_block
      end
    end)

    # Use stub_const to manage ConsoleKit::Railtie
    stub_const('ConsoleKit::Railtie', Class.new(Rails::Railtie))
    load File.expand_path('../../lib/console_kit/railtie.rb', __dir__)
  end

  it 'defines Railtie' do
    expect(defined?(ConsoleKit::Railtie)).to be_truthy
  end

  it 'inherits from Rails::Railtie' do
    expect(ConsoleKit::Railtie).to be < Rails::Railtie
  end

  describe 'console hook' do
    it 'registers a console block' do
      expect(ConsoleKit::Railtie.console_block).to be_a(Proc)
    end

    it 'calls Setup.setup when the console block is executed' do
      allow(ConsoleKit::Setup).to receive(:setup)
      ConsoleKit::Railtie.console_block.call
      expect(ConsoleKit::Setup).to have_received(:setup)
    end

    it 'extends main when neither Pry nor IRB::ExtendCommandBundle is defined' do
      hide_const('Pry') if defined?(Pry)
      hide_const('IRB::ExtendCommandBundle') if defined?(IRB::ExtendCommandBundle)
      allow(ConsoleKit::Setup).to receive(:setup)
      allow(ConsoleKit::Prompt).to receive(:apply)

      receiver = TOPLEVEL_BINDING.receiver
      expect(receiver).to receive(:extend).with(ConsoleKit::ConsoleHelpers)

      ConsoleKit::Railtie.console_block.call
    end
  end

  describe 'to_prepare hook' do
    it 'calls Setup.reapply if in a console session' do
      stub_const('Rails::Console', Class.new)
      allow(ConsoleKit::Setup).to receive(:reapply)

      # Manually trigger the to_prepare blocks
      ConsoleKit::Railtie.config.to_prepare_blocks.each(&:call)

      expect(ConsoleKit::Setup).to have_received(:reapply)
    end

    it 'does not call Setup.reapply if not in a console session' do
      hide_const('Rails::Console')
      allow(ConsoleKit::Setup).to receive(:reapply)

      ConsoleKit::Railtie.config.to_prepare_blocks.each(&:call)

      expect(ConsoleKit::Setup).not_to have_received(:reapply)
    end
  end
end
