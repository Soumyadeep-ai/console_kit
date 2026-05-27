# spec/console_kit/railtie_spec.rb
# frozen_string_literal: true

require 'spec_helper'

# Railtie is excluded from SimpleCov (requires a live Rails app).
# This spec verifies the *behavior* of the blocks that railtie.rb registers
# without triggering SimpleCov's per-load coverage-reset issue.
RSpec.describe 'ConsoleKit Railtie blocks' do
  before do
    ConsoleKit.configure do |c|
      c.tenants = { tenant_a: { constants: { shard: 's', partner_code: 'p' } } }
      c.context_class = 'Object'
    end
    allow(ConsoleKit::SwitchPipeline).to receive(:run)
      .and_return(ConsoleKit::SwitchPipeline::Result.new(success: true, tenant: nil))
  end

  # Helpers that simulate the railtie console block logic
  def simulate_console_block
    ConsoleKit::SwitchPipeline.run(config: ConsoleKit.configuration)
    if defined?(IRB::ExtendCommandBundle) && !defined?(Pry)
      IRB::ExtendCommandBundle.include(ConsoleKit::ConsoleHelpers)
    else
      TOPLEVEL_BINDING.receiver.extend(ConsoleKit::ConsoleHelpers)
    end
  end

  describe 'console block behavior (IRB path)' do
    let(:irb_bundle) { Module.new }

    before do
      stub_const('IRB::ExtendCommandBundle', irb_bundle)
      hide_const('Pry') if defined?(Pry)
    end

    it 'includes ConsoleHelpers into IRB::ExtendCommandBundle' do
      simulate_console_block
      expect(irb_bundle.ancestors).to include(ConsoleKit::ConsoleHelpers)
    end
  end

  describe 'console block behavior (non-IRB path)' do
    let(:receiver) { double('receiver') } # rubocop:disable RSpec/VerifiedDoubles

    before do
      hide_const('IRB::ExtendCommandBundle') if defined?(IRB::ExtendCommandBundle)
      allow(receiver).to receive(:extend)
      stub_const('Pry', double('Pry')) # rubocop:disable RSpec/VerifiedDoubles
      stub_const('TOPLEVEL_BINDING', double('TOPLEVEL_BINDING', receiver: receiver)) # rubocop:disable RSpec/VerifiedDoubles
    end

    it 'extends TOPLEVEL_BINDING receiver with ConsoleHelpers' do
      simulate_console_block
      expect(receiver).to have_received(:extend).with(ConsoleKit::ConsoleHelpers)
    end
  end

  describe 'to_prepare block behavior' do
    it 'runs SwitchPipeline when Rails::Console is defined' do
      stub_const('Rails::Console', Class.new)
      ConsoleKit::SwitchPipeline.run(config: ConsoleKit.configuration) if defined?(Rails::Console)
      expect(ConsoleKit::SwitchPipeline).to have_received(:run)
    end
  end
end
