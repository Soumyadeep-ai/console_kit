# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Steps::PresetApplier do
  subject(:step) { described_class.new(ctx) }

  let(:config) { ConsoleKit.configuration }
  let(:ctx)    { ConsoleKit::PipelineContext.new(config: config) }

  before do
    ConsoleKit.configure do |c|
      c.tenants = { tenant_a: { constants: { shard: 's1', partner_code: 'pa' } } }
      c.context_class = 'Object'
      c.presets = {
        support: { readonly_mode: true },
        readonly_ops: { readonly_environments: %w[production staging] }
      }
    end
    allow(ConsoleKit::Output).to receive(:print_info)
  end

  after { ENV.delete('CONSOLE_KIT_ROLE') }

  context 'when CONSOLE_KIT_ROLE is not set' do
    it 'returns success' do
      expect(step.call.success?).to be true
    end

    it 'does not change config' do
      step.call
      expect(config.readonly_mode).to be false
    end

    it 'does not print preset info' do
      step.call
      expect(ConsoleKit::Output).not_to have_received(:print_info)
    end
  end

  context 'when CONSOLE_KIT_ROLE matches a preset (symbol key)' do
    before { ENV['CONSOLE_KIT_ROLE'] = 'support' }

    it 'returns success' do
      expect(step.call.success?).to be true
    end

    it 'applies preset overrides to config' do
      step.call
      expect(config.readonly_mode).to be true
    end

    it 'prints preset active info' do
      step.call
      expect(ConsoleKit::Output).to have_received(:print_info).with(/support/)
    end
  end

  context 'when CONSOLE_KIT_ROLE matches a preset with array value' do
    before { ENV['CONSOLE_KIT_ROLE'] = 'readonly_ops' }

    it 'applies the array override' do
      step.call
      expect(config.readonly_environments).to eq(%w[production staging])
    end
  end

  context 'when CONSOLE_KIT_ROLE is set but not found in presets' do
    before { ENV['CONSOLE_KIT_ROLE'] = 'nonexistent_role' }

    it 'returns failure' do
      expect(step.call.failure?).to be true
    end

    it 'includes role name in error message' do
      result = step.call
      expect(result.error).to include('nonexistent_role')
    end
  end

  context 'when presets is empty' do
    before do
      config.presets = {}
      ENV['CONSOLE_KIT_ROLE'] = 'support'
    end

    it 'returns failure' do
      expect(step.call.failure?).to be true
    end
  end

  context 'when preset has string key and role is given as string' do
    before do
      config.presets = { 'ops' => { readonly_mode: true } }
      ENV['CONSOLE_KIT_ROLE'] = 'ops'
    end

    it 'matches string key' do
      step.call
      expect(config.readonly_mode).to be true
    end
  end
end
