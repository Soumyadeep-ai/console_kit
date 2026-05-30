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

    it 'reprints the menu after invalid inputs before final retry' do
      allow($stdin).to receive(:gets).and_return("bad\n", "nope\n", "0\n")
      allow(ConsoleKit::Output).to receive(:print_info)
      allow(ConsoleKit::Output).to receive(:print_header)
      described_class.select(tenants, keys)
      expect(ConsoleKit::Output).to have_received(:print_header).exactly(3).times # once + 2 reprints
    end
  end

  context 'when called with no arguments (defaults from configuration)' do
    before do
      ConsoleKit.configure do |c|
        c.tenants = { alpha: { constants: { partner_code: 'ALPHA' } } }
        c.context_class = 'Object'
      end
    end

    it 'resolves tenants and keys from configuration' do
      allow($stdin).to receive(:gets).and_return("1\n")
      expect(described_class.select).to eq(:alpha)
    end
  end

  context 'when called with no arguments and tenants is :dynamic' do
    before do
      ConsoleKit.configure do |c|
        c.tenants = :dynamic
        c.tenant_resolver = ->(key) { key }
        c.context_class = 'Object'
      end
    end

    it 'uses empty keys list and returns nil' do
      allow($stdin).to receive(:gets).and_return("0\n")
      expect(described_class.select).to be_nil
    end
  end

  context 'when tenants is not a Hash (non-Hash resolver)' do
    let(:resolver) { instance_double(ConsoleKit::TenantResolver) }

    before do
      ConsoleKit.configure do |c|
        c.tenants = { 'alpha' => { constants: { partner_code: 'ALPHA' } } }
        c.context_class = 'Object'
      end
      allow(ConsoleKit.configuration).to receive(:tenant_resolver_instance).and_return(resolver)
      allow(resolver).to receive(:all_keys).and_return(['alpha'])
      allow(ConsoleKit::Output).to receive(:print_info)
      allow(ConsoleKit::Output).to receive(:print_header)
    end

    it 'looks up partner code via resolver when tenants is not a Hash' do
      allow(resolver).to receive(:resolve).with('alpha').and_return({ constants: { partner_code: 'ALPHA' } })
      allow($stdin).to receive(:gets).and_return("1\n")
      described_class.select('not_a_hash', ['alpha'])
      expect(resolver).to have_received(:resolve).with('alpha')
    end

    it 'shows N/A when resolver returns nil for partner code' do
      allow(resolver).to receive(:resolve).with('alpha').and_return(nil)
      allow($stdin).to receive(:gets).and_return("1\n")
      described_class.select('not_a_hash', ['alpha'])
      expect(ConsoleKit::Output).to have_received(:print_info).with('  1. alpha (partner: N/A)')
    end
  end

  context 'when validating integer inputs' do
    it 'returns false for non-digit inputs' do
      expect(described_class.send(:valid_integer?, 'bad')).to be false
    end

    it 'returns false for alphanumeric inputs' do
      expect(described_class.send(:valid_integer?, '123abc')).to be false
    end

    it 'returns false for empty string' do
      expect(described_class.send(:valid_integer?, '')).to be false
    end

    it 'returns true for zero' do
      expect(described_class.send(:valid_integer?, '0')).to be true
    end

    it 'returns true for multi-digit numbers' do
      expect(described_class.send(:valid_integer?, '15')).to be true
    end

    it 'uses "1" when user presses enter (empty input)' do
      allow(ConsoleKit::Output).to receive(:print_prompt)
      allow($stdin).to receive(:gets).and_return("\n")
      expect(described_class.select(tenants, keys)).to eq('alpha')
    end

    it 'defaults to "0" (no tenant) when no tenants available and input is empty' do
      allow($stdin).to receive(:gets).and_return("\n")
      expect(described_class.select({}, [])).to be_nil
    end
  end

  context 'when using name prefix matching' do
    it 'returns tenant matching unique prefix' do
      allow($stdin).to receive(:gets).and_return("al\n")
      expect(described_class.select(tenants, keys)).to eq('alpha')
    end

    it 'returns tenant matching full name' do
      allow($stdin).to receive(:gets).and_return("beta\n")
      expect(described_class.select(tenants, keys)).to eq('beta')
    end

    it 'warns and retries on ambiguous prefix' do
      allow($stdin).to receive(:gets).and_return("a\n", "1\n")
      ambiguous_tenants = { 'apple' => { constants: { partner_code: 'AP' } }, 'android' => { constants: { partner_code: 'AN' } } }
      ambiguous_keys = ambiguous_tenants.keys
      allow(ConsoleKit::Output).to receive(:print_warning).with(a_string_including('Ambiguous'))
      described_class.select(ambiguous_tenants, ambiguous_keys)
      expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('Ambiguous'))
    end

    it 'warns and retries on no match' do
      allow($stdin).to receive(:gets).and_return("xyz\n", "1\n")
      allow(ConsoleKit::Output).to receive(:print_warning).with("No tenant matches 'xyz'.")
      described_class.select(tenants, keys)
      expect(ConsoleKit::Output).to have_received(:print_warning).with("No tenant matches 'xyz'.")
    end

    it 'warns about input selection being out of range' do
      allow($stdin).to receive(:gets).and_return("9\n", "1\n")
      allow(ConsoleKit::Output).to receive(:print_warning).with('Selection must be between 0 and 2.')
      described_class.select(tenants, keys)
      expect(ConsoleKit::Output).to have_received(:print_warning).with('Selection must be between 0 and 2.')
    end

    it 'strips surrounding whitespace from input' do
      allow($stdin).to receive(:gets).and_return(" 2 \n")
      expect(described_class.select(tenants, keys)).to eq('beta')
    end

    it 'treats nil from gets as empty input and defaults to first tenant' do
      # gets returns nil at EOF — normalize_input treats nil.to_s as empty, so uses default '1'
      allow($stdin).to receive(:gets).and_return(nil)
      result = described_class.select(tenants, keys)
      expect(result).to eq('alpha')
    end
  end
end
