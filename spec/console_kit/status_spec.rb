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
end
