# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::TenantSelector do
  let(:tenants) do
    {
      'alpha' => { constants: { partner_code: 'ALPHA' } },
      'beta' => { constants: { partner_code: 'BETA' } }
    }
  end

  let(:keys) { tenants.keys }

  it 'selects default tenant when user presses Enter' do
    allow($stdin).to receive(:gets).and_return("\n")
    expect(described_class.select(tenants, keys)).to eq('alpha')
  end

  it 'returns nil if 0 is selected' do
    allow($stdin).to receive(:gets).and_return("0\n")
    expect(described_class.select(tenants, keys)).to be_nil
  end

  it 'returns tenant by valid index' do
    allow($stdin).to receive(:gets).and_return("2\n")
    expect(described_class.select(tenants, keys)).to eq('beta')
  end

  it 'retries on invalid input' do
    allow($stdin).to receive(:gets).and_return("invalid\n", "1\n")
    expect(described_class.select(tenants, keys)).to eq('alpha')
  end
end
