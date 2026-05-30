# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Status do
  subject(:status) { described_class.build }

  before do
    ConsoleKit.configure do |c|
      c.tenants = { tenant_a: { constants: { shard: 's1', partner_code: 'pa' } } }
      c.context_class = 'Object'
    end
    ConsoleKit::Context.push(:tenant_a)
    ConsoleKit::Context.mark_configured!
  end

  after { ConsoleKit::Context.reset! }

  it 'returns current tenant' do
    expect(status.tenant).to eq(:tenant_a)
  end

  it 'returns configured true when context configured' do
    expect(status.configured).to be true
  end

  it 'prints without error' do
    expect { status.print }.not_to raise_error
  end

  it 'uses Rails.env when Rails responds to :env' do
    # Stub Rails to respond to :env with a mock env
    rails_mock = double('Rails', env: double('env', to_s: 'test')) # rubocop:disable RSpec/VerifiedDoubles
    stub_const('Rails', rails_mock)
    s = described_class.build
    expect(s.env).to eq('test')
  end

  it 'uses RAILS_ENV from ENV when Rails not defined' do
    hide_const('Rails') if defined?(Rails)
    stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'staging'))
    s = described_class.build
    expect(s.env).to eq('staging')
  end

  it 'returns unknown when Rails absent and RAILS_ENV not set' do
    hide_const('Rails') if defined?(Rails)
    stub_const('ENV', ENV.to_h.except('RAILS_ENV'))
    s = described_class.build
    expect(s.env).to eq('unknown')
  end
end
