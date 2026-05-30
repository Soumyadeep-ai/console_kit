# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Steps::WelcomeBanner do
  subject(:step) { described_class.new(ctx) }

  let(:config) { ConsoleKit.configuration }
  let(:ctx)    { ConsoleKit::PipelineContext.new(config: config) }

  before do
    ConsoleKit.configure do |c|
      c.tenants = { tenant_a: { constants: { shard: 's1', partner_code: 'pa' } } }
      c.context_class = 'Object'
    end
    allow(ConsoleKit::Output).to receive(:print_header)
  end

  it 'returns success' do
    expect(step.call.success?).to be true
  end

  it 'prints header with version' do
    step.call
    expect(ConsoleKit::Output).to have_received(:print_header).with(
      a_string_including(ConsoleKit::VERSION)
    )
  end

  it 'prints header with current env' do
    hide_const('Rails')
    stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'staging'))
    step.call
    expect(ConsoleKit::Output).to have_received(:print_header).with(a_string_including('staging'))
  end

  context 'when scoped (ConsoleKit.with block)' do
    before { ctx.scoped = true }

    it 'returns success without printing' do
      step.call
      expect(ConsoleKit::Output).not_to have_received(:print_header)
    end
  end

  context 'when Rails.env is defined' do
    before do
      rails_double = double('Rails') # rubocop:disable RSpec/VerifiedDoubles
      allow(rails_double).to receive(:respond_to?).with(:env).and_return(true)
      allow(rails_double).to receive(:env).and_return(double('env', to_s: 'production')) # rubocop:disable RSpec/VerifiedDoubles
      stub_const('Rails', rails_double)
    end

    it 'includes Rails.env in header' do
      step.call
      expect(ConsoleKit::Output).to have_received(:print_header).with(a_string_including('production'))
    end
  end

  context 'when neither RAILS_ENV nor RACK_ENV set' do
    before do
      hide_const('Rails')
      stub_const('ENV', ENV.to_h.except('RAILS_ENV', 'RACK_ENV'))
    end

    it 'falls back to development' do
      step.call
      expect(ConsoleKit::Output).to have_received(:print_header).with(a_string_including('development'))
    end
  end
end
