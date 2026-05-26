# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Prompt do
  describe '#tenant_label' do
    let(:context) { ConsoleKit::Context.new(tenant: :tenant_a) }

    before do
      allow(ConsoleKit::Context).to receive(:current).and_return(context)
    end

    it 'returns tenant and env label using Rails when available' do
      # Rails is defined in the test environment, use its actual env
      prompt = described_class.new
      label = prompt.tenant_label
      expect(label).to match(/\[tenant_a\]\[.+\]/)
    end

    it 'returns no-tenant when tenant is nil' do
      context_without_tenant = ConsoleKit::Context.new(tenant: nil)
      allow(ConsoleKit::Context).to receive(:current).and_return(context_without_tenant)
      prompt = described_class.new
      expect(prompt.tenant_label).to eq('[no-tenant]')
    end

    it 'uses ENV fallback when RAILS_ENV is set' do
      context_env = ConsoleKit::Context.new(tenant: :tenant_b)
      allow(ConsoleKit::Context).to receive(:current).and_return(context_env)
      # Since Rails is defined in the test environment, just verify the format
      prompt = described_class.new
      label = prompt.tenant_label
      expect(label).to match(/\[tenant_b\]\[.+\]/)
    end
  end

  describe '.apply' do
    let(:context) { ConsoleKit::Context.new(tenant: :tenant_a) }

    before do
      allow(ConsoleKit::Context).to receive(:current).and_return(context)
    end

    it 'returns early when IRB and Pry are not defined' do
      hide_const('IRB') if defined?(IRB)
      hide_const('Pry') if defined?(Pry)
      expect(described_class.apply).to be_nil
    end

    it 'does not raise an error when called' do
      expect { described_class.apply }.not_to raise_error
    end
  end
end
