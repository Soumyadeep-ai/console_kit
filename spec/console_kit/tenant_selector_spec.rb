# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::TenantSelector do
  let(:tenants) do
    { 'alpha' => { constants: { partner_code: 'ALPHA' } }, 'beta' => { constants: { partner_code: 'BETA' } } }
  end

  before { allow(ConsoleKit).to receive(:tenants).and_return(tenants) }

  describe '.select' do
    context 'when valid input is given' do
      it 'returns the selected tenant key for input "1"' do
        allow($stdin).to receive(:gets).and_return("1\n")
        expect(described_class.select).to eq('alpha')
      end

      it 'returns the selected tenant key for input "2"' do
        allow($stdin).to receive(:gets).and_return("2\n")
        expect(described_class.select).to eq('beta')
      end

      it 'returns nil if user selects 0 (load without tenant)' do
        allow($stdin).to receive(:gets).and_return("0\n")
        expect(described_class.select).to be_nil
      end

      it 'defaults to "1" if input is empty' do
        allow($stdin).to receive(:gets).and_return("\n")
        expect(described_class.select).to eq('alpha')
      end

      it 'strips surrounding whitespace from input' do
        allow($stdin).to receive(:gets).and_return(" 2 \n")
        expect(described_class.select).to eq('beta')
      end
    end

    context 'when invalid input is given' do
      it 'retries up to 3 times and returns nil if never valid' do
        allow($stdin).to receive(:gets).and_return("bad\n", "-1\n", "5\n")
        expect(described_class.select).to be_nil
      end

      it 'retries on invalid inputs then succeeds on a valid input' do
        allow($stdin).to receive(:gets).and_return("bad\n", "nope\n", "2\n")
        expect(described_class.select).to eq('beta')
      end

      it 'reprints the menu after invalid inputs before final retry' do
        allow($stdin).to receive(:gets).and_return("bad\n", "nope\n", "0\n")
        allow(ConsoleKit::Output).to receive(:print_header)

        described_class.select

        expect(ConsoleKit::Output).to have_received(:print_header).exactly(3).times
      end

      it 'warns about input selection being out of range' do
        allow($stdin).to receive(:gets).and_return("9\n", "1\n")
        allow(ConsoleKit::Output).to receive(:print_warning)

        described_class.select

        expect(ConsoleKit::Output).to have_received(:print_warning).with('Selection must be between 0 and 2.')
      end
    end

    context 'when prompting the user' do
      it 'calls print_prompt when reading input' do
        allow($stdin).to receive(:gets).and_return("\n")
        allow(ConsoleKit::Output).to receive(:print_prompt)

        described_class.select

        expect(ConsoleKit::Output).to have_received(:print_prompt)
      end
    end

    context 'when handling edge cases' do
      it 'selects correctly when only one tenant exists' do
        single_tenant = { 'gamma' => { constants: { partner_code: 'GAMMA' } } }
        allow(ConsoleKit).to receive(:tenants).and_return(single_tenant)
        allow($stdin).to receive(:gets).and_return("1\n")
        expect(described_class.select).to eq('gamma')
      end

      it 'returns nil for "0" even when only one tenant exists' do
        allow(ConsoleKit).to receive(:tenants).and_return({ 'alpha' => {} })
        allow($stdin).to receive(:gets).and_return("0\n")
        expect(described_class.select).to be_nil
      end
    end
  end

  describe 'input validation' do
    it 'returns false for non-digit input "bad"' do
      expect(described_class.send(:valid_integer?, 'bad')).to be false
    end

    it 'returns false for mixed input "123abc"' do
      expect(described_class.send(:valid_integer?, '123abc')).to be false
    end

    it 'returns false for empty input' do
      expect(described_class.send(:valid_integer?, '')).to be false
    end

    it 'returns true for "0"' do
      expect(described_class.send(:valid_integer?, '0')).to be true
    end

    it 'returns true for "15"' do
      expect(described_class.send(:valid_integer?, '15')).to be true
    end
  end
end
