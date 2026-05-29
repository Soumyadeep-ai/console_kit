# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Steps::StartupSummary do
  subject(:step) { described_class.new(ctx) }

  let(:config) { ConsoleKit.configuration }
  let(:ctx)    { ConsoleKit::PipelineContext.new(config: config) }

  before do
    ConsoleKit.configure do |c|
      c.tenants = { tenant_a: { constants: { shard: 's1', partner_code: 'pa' } } }
      c.context_class = 'Object'
    end
    ctx.resolved_tenant = :tenant_a
    hide_const('Rails')
    stub_const('ENV', ENV.to_h.except('RAILS_ENV', 'RACK_ENV', 'CONSOLE_KIT_ROLE'))
    allow(ConsoleKit::Output).to receive(:print_success)
  end

  after { ConsoleKit::ReadonlyMode.deactivate! }

  it 'returns success' do
    expect(step.call.success?).to be true
  end

  it 'prints tenant in summary' do
    step.call
    expect(ConsoleKit::Output).to have_received(:print_success).with(a_string_including('tenant_a'))
  end

  it 'prints env in summary' do
    step.call
    expect(ConsoleKit::Output).to have_received(:print_success).with(a_string_including('development'))
  end

  context 'when no tenant resolved' do
    before { ctx.resolved_tenant = nil }

    it 'returns success without printing' do
      step.call
      expect(ConsoleKit::Output).not_to have_received(:print_success)
    end
  end

  context 'when scoped switch' do
    before { ctx.scoped = true }

    it 'returns success without printing' do
      step.call
      expect(ConsoleKit::Output).not_to have_received(:print_success)
    end
  end

  context 'when readonly mode active' do
    before do
      ConsoleKit::ReadonlyMode.activate!
    end

    it 'includes readonly: ON in summary' do
      step.call
      expect(ConsoleKit::Output).to have_received(:print_success).with(a_string_including('readonly: ON'))
    end
  end

  context 'when readonly mode not active' do
    it 'does not include readonly label' do
      step.call
      expect(ConsoleKit::Output).to have_received(:print_success).with(
        satisfy { |s| !s.include?('readonly') }
      )
    end
  end

  context 'when CONSOLE_KIT_ROLE is set' do
    before { stub_const('ENV', ENV.to_h.merge('CONSOLE_KIT_ROLE' => 'support')) }

    it 'includes preset label in summary' do
      step.call
      expect(ConsoleKit::Output).to have_received(:print_success).with(a_string_including('preset: support'))
    end
  end

  context 'when CONSOLE_KIT_ROLE is not set' do
    it 'does not include preset label' do
      step.call
      expect(ConsoleKit::Output).to have_received(:print_success).with(
        satisfy { |s| !s.include?('preset') }
      )
    end
  end

  context 'when Rails.env defined' do
    before do
      rails_double = double('Rails') # rubocop:disable RSpec/VerifiedDoubles
      allow(rails_double).to receive(:respond_to?).with(:env).and_return(true)
      allow(rails_double).to receive(:env).and_return(double('env', to_s: 'production')) # rubocop:disable RSpec/VerifiedDoubles
      stub_const('Rails', rails_double)
    end

    it 'uses Rails.env in summary' do
      step.call
      expect(ConsoleKit::Output).to have_received(:print_success).with(a_string_including('production'))
    end
  end
end
