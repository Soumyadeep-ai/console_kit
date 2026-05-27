# spec/console_kit/console_helpers_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::ConsoleHelpers do
  subject(:obj) { Object.new.extend(described_class) }

  before do
    ConsoleKit.configure do |c|
      c.tenants = { tenant_a: {}, tenant_b: {} }
      c.context_class = 'Object'
    end
  end

  after { ConsoleKit::Context.reset! }

  describe '#switch_tenant' do
    it 'delegates to ConsoleKit.switch_tenant!' do
      allow(ConsoleKit).to receive(:switch_tenant!)
      obj.switch_tenant
      expect(ConsoleKit).to have_received(:switch_tenant!)
    end
  end

  describe '#tenant_info' do
    it 'calls print on the status object' do
      status = instance_double(ConsoleKit::Status)
      allow(ConsoleKit).to receive(:status).and_return(status)
      allow(status).to receive(:print)
      obj.tenant_info
      expect(status).to have_received(:print)
    end
  end

  describe '#tenants' do
    it 'returns tenant keys as array' do
      expect(obj.tenants).to eq(%i[tenant_a tenant_b])
    end

    it 'returns [:dynamic_mode] when tenants is :dynamic' do
      ConsoleKit.configure { |c| c.tenants = :dynamic }
      expect(obj.tenants).to eq([:dynamic_mode])
    end

    it 'returns empty array when ConsoleKit::Error is raised' do
      allow(ConsoleKit.configuration).to receive(:tenant_resolver_instance)
        .and_raise(ConsoleKit::Error, 'no tenants')
      expect(obj.tenants).to eq([])
    end
  end
end
