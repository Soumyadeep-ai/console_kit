# spec/console_kit/steps/safeguard_check_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Steps::SafeguardCheck do
  subject(:step) { described_class.new(ctx) }

  let(:config) { ConsoleKit.configuration }
  let(:ctx)    { ConsoleKit::PipelineContext.new(config: config, scoped: false) }

  before do
    ConsoleKit.configure do |c|
      c.tenants       = { tenant_a: { constants: { shard: 's1', partner_code: 'pa' } } }
      c.context_class = 'Object'
    end
    ctx.resolved_tenant = :tenant_a
  end

  context 'when not a dangerous environment' do
    before { stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'development', 'RACK_ENV' => 'development')) }

    it 'returns success without prompting' do
      expect(step.call.success?).to be true
    end
  end

  context 'when in production environment' do
    before do
      stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'production', 'RACK_ENV' => 'production'))
      allow(ConsoleKit::Output).to receive(:print_banner)
    end

    it 'prints banner' do
      config.confirm_dangerous_context = false
      step.call
      expect(ConsoleKit::Output).to have_received(:print_banner)
    end

    it 'returns success when confirm_dangerous_context is false' do
      config.confirm_dangerous_context = false
      expect(step.call.success?).to be true
    end

    context 'when confirm_dangerous_context is true' do
      before { config.confirm_dangerous_context = true }

      it 'returns success when user types CONFIRM' do
        allow($stdin).to receive(:gets).and_return("CONFIRM\n")
        allow(ConsoleKit::Output).to receive(:print_prompt)
        expect(step.call.success?).to be true
      end

      it 'returns failure when user types wrong input' do
        allow($stdin).to receive(:gets).and_return("no\n")
        allow(ConsoleKit::Output).to receive(:print_prompt)
        expect(step.call.failure?).to be true
      end

      it 'returns false when Interrupt is raised during confirmation' do
        allow($stdin).to receive(:gets).and_raise(Interrupt)
        allow(ConsoleKit::Output).to receive(:print_prompt)
        expect(step.call.failure?).to be true
      end

      it 'returns failure when gets returns nil (EOF)' do
        allow($stdin).to receive(:gets).and_return(nil)
        allow(ConsoleKit::Output).to receive(:print_prompt)
        expect(step.call.failure?).to be true
      end
    end
  end

  context 'when tenant is protected' do
    before do
      stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'development', 'RACK_ENV' => 'development'))
      allow(ConsoleKit::Output).to receive(:print_banner)
      config.protected_tenants = [:tenant_a]
    end

    it 'prints banner for protected tenant' do
      config.confirm_dangerous_context = false
      step.call
      expect(ConsoleKit::Output).to have_received(:print_banner)
    end
  end

  context 'when ctx.scoped is true' do
    let(:ctx) { ConsoleKit::PipelineContext.new(config: config, scoped: true) }

    it 'skips check and returns success' do
      stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'production', 'RACK_ENV' => 'production'))
      expect(step.call.success?).to be true
    end
  end

  context 'when Rails responds to :env and returns production' do
    before do
      rails_mock = double('Rails', env: double('env', to_s: 'production')) # rubocop:disable RSpec/VerifiedDoubles
      stub_const('Rails', rails_mock)
      config.production_environments = ['production']
      allow(ConsoleKit::Output).to receive(:print_banner)
    end

    it 'detects production via Rails.env' do
      config.confirm_dangerous_context = false
      step.call
      expect(ConsoleKit::Output).to have_received(:print_banner)
    end
  end

  context 'when Rails is not defined and only RACK_ENV is set' do
    before do
      allow(Rails).to receive(:respond_to?).with(:env).and_return(false)
      stub_const('ENV', { 'RACK_ENV' => 'production' })
      allow(ConsoleKit::Output).to receive(:print_banner)
    end

    it 'detects production via RACK_ENV' do
      config.confirm_dangerous_context = false
      step.call
      expect(ConsoleKit::Output).to have_received(:print_banner)
    end
  end

  context 'when Rails is not defined and no env vars set' do
    before do
      allow(Rails).to receive(:respond_to?).with(:env).and_return(false)
      stub_const('ENV', {})
    end

    it 'defaults to development and returns success' do
      expect(step.call.success?).to be true
    end
  end
end
