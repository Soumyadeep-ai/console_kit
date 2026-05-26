# spec/console_kit/context_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Context do
  after { described_class.reset! }

  describe '.current' do
    it 'returns a Context instance' do
      expect(described_class.current).to be_a(described_class)
    end

    it 'returns nil tenant by default' do
      expect(described_class.current.tenant).to be_nil
    end

    it 'returns false configuration_success by default' do
      expect(described_class.current.configuration_success).to be false
    end
  end

  describe '.push and .pop' do
    it 'sets tenant to pushed value' do
      described_class.push(:tenant_a)
      expect(described_class.current.tenant).to eq(:tenant_a)
    end

    it 'restores previous tenant after pop' do
      described_class.push(:tenant_a)
      described_class.push(:tenant_b)
      described_class.pop
      expect(described_class.current.tenant).to eq(:tenant_a)
    end

    it 'returns previous tenant from pop' do
      described_class.push(:tenant_a)
      described_class.push(:tenant_b)
      expect(described_class.pop).to eq(:tenant_a)
    end

    it 'restores nil when popping last entry' do
      described_class.push(:tenant_a)
      described_class.pop
      expect(described_class.current.tenant).to be_nil
    end
  end

  describe '.mark_configured!' do
    it 'sets configuration_success to true' do
      described_class.push(:tenant_a)
      described_class.mark_configured!
      expect(described_class.current.configuration_success).to be true
    end

    it 'preserves the current tenant' do
      described_class.push(:tenant_a)
      described_class.mark_configured!
      expect(described_class.current.tenant).to eq(:tenant_a)
    end
  end

  describe '.reset!' do
    it 'clears current tenant' do
      described_class.push(:tenant_a)
      described_class.reset!
      expect(described_class.current.tenant).to be_nil
    end

    context 'when reset clears the stack' do
      before do
        described_class.push(:tenant_a)
        described_class.push(:tenant_b)
        described_class.reset!
        described_class.push(:tenant_c)
        described_class.pop
      end

      it 'leaves no previous tenant to restore' do
        expect(described_class.current.tenant).to be_nil
      end
    end
  end

  describe '#configured?' do
    it 'returns false when tenant is nil' do
      expect(described_class.current.configured?).to be false
    end

    it 'returns false when tenant set but configuration_success false' do
      described_class.push(:tenant_a)
      expect(described_class.current.configured?).to be false
    end

    it 'returns true when tenant set and configuration_success true' do
      described_class.push(:tenant_a)
      described_class.mark_configured!
      expect(described_class.current.configured?).to be true
    end
  end
end
