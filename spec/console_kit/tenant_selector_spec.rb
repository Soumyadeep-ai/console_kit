# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::TenantSelector do
  let(:tenants) do
    { 'alpha' => { constants: { partner_code: 'ALPHA' } }, 'beta' => { constants: { partner_code: 'BETA' } } }
  end

  let(:keys) { tenants.keys }

  context 'when valid input is given' do
    it 'returns the selected tenant key for input "1"' do
      allow($stdin).to receive(:gets).and_return("1\n")
      expect(described_class.select(tenants, keys)).to eq('alpha')
    end

    it 'returns the selected tenant key for input "2"' do
      allow($stdin).to receive(:gets).and_return("2\n")
      expect(described_class.select(tenants, keys)).to eq('beta')
    end

    it 'returns nil if user selects 0 (load without tenant)' do
      allow($stdin).to receive(:gets).and_return("0\n")
      expect(described_class.select(tenants, keys)).to be_nil
    end

    it 'defaults to "1" if input is empty' do
      allow($stdin).to receive(:gets).and_return("\n")
      expect(described_class.select(tenants, keys)).to eq('alpha')
    end
  end

  context 'when invalid input is given' do
    it 'retries up to 3 times and returns nil if never valid' do
      allow($stdin).to receive(:gets).and_return("bad\n", "-1\n", "3\n")
      expect(described_class.select(tenants, keys)).to be_nil
    end

    it 'retries on invalid inputs then succeeds on a valid input' do
      allow($stdin).to receive(:gets).and_return("bad\n", "nope\n", "2\n")
      expect(described_class.select(tenants, keys)).to eq('beta')
    end
  end

  context 'input validation' do
    it 'returns -1 for non-digit inputs' do
      expect(described_class.send(:valid_integer?, 'bad')).to be false
      expect(described_class.send(:valid_integer?, '123abc')).to be false
      expect(described_class.send(:valid_integer?, '')).to be false
    end

    it 'returns true for valid digit strings' do
      expect(described_class.send(:valid_integer?, '0')).to be true
      expect(described_class.send(:valid_integer?, '15')).to be true
    end
  end
end
