# spec/console_kit/tenant_resolver_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::TenantResolver do
  describe '.build — Hash format' do
    subject(:resolver) { described_class.build(tenants, nil) }

    let(:tenants) { { tenant_a: { constants: { shard: 's', partner_code: 'p' } } } }

    it 'returns all keys' do
      expect(resolver.all_keys).to eq([:tenant_a])
    end

    it 'resolves constants for key' do
      expect(resolver.resolve(:tenant_a)).to eq(tenants[:tenant_a])
    end

    it 'returns nil for unknown key' do
      expect(resolver.resolve(:unknown)).to be_nil
    end

    it 'reports any? true' do
      expect(resolver.any?).to be true
    end

    it 'reports correct size' do
      expect(resolver.size).to eq(1)
    end

    it 'resolves by string when hash has symbol keys' do
      expect(resolver.resolve('tenant_a')).not_to be_nil
    end

    context 'with string-keyed hash' do
      subject(:resolver) { described_class.build({ 'acme' => { constants: { shard: 's', partner_code: 'p' } } }, nil) }

      it 'resolves by symbol key' do
        expect(resolver.resolve(:acme)).not_to be_nil
      end

      it 'resolves by string key' do
        expect(resolver.resolve('acme')).not_to be_nil
      end
    end
  end

  describe '.build — Array format' do
    subject(:resolver) { described_class.build(%i[tenant_a tenant_b], resolver_proc) }

    let(:resolver_proc) { ->(key) { { constants: { shard: "#{key}_db", partner_code: key.to_s } } } }

    it 'returns all keys from array' do
      expect(resolver.all_keys).to eq(%i[tenant_a tenant_b])
    end

    it 'resolves via proc' do
      expect(resolver.resolve(:tenant_a)).to eq(resolver_proc.call(:tenant_a))
    end

    it 'returns nil when proc returns nil' do
      null_proc = ->(_key) {}
      r = described_class.build(%i[tenant_a], null_proc)
      expect(r.resolve(:tenant_a)).to be_nil
    end

    it 'returns nil when resolver_proc is nil (safe navigation &.)' do
      r = described_class.build(%i[tenant_a], nil)
      expect(r.resolve(:tenant_a)).to be_nil
    end

    it 'reports any? true' do
      expect(resolver.any?).to be true
    end

    it 'reports correct size' do
      expect(resolver.size).to eq(2)
    end
  end

  describe '.build — :dynamic format' do
    subject(:resolver) { described_class.build(:dynamic, resolver_proc) }

    let(:resolver_proc) do
      ->(key) { key == :tenant_a ? { constants: { shard: 'db_a', partner_code: 'pa' } } : nil }
    end

    it 'resolves via proc' do
      expect(resolver.resolve(:tenant_a)).not_to be_nil
    end

    it 'returns nil for unknown key' do
      expect(resolver.resolve(:unknown)).to be_nil
    end

    it 'raises when all_keys called' do
      expect { resolver.all_keys }
        .to raise_error(ConsoleKit::Error, /all_keys not available in :dynamic mode/)
    end

    it 'reports any? true' do
      expect(resolver.any?).to be true
    end

    it 'raises for size' do
      expect { resolver.size }.to raise_error(ConsoleKit::Error, /size not available in :dynamic mode/)
    end

    it 'returns nil when resolver_proc is nil (safe navigation &.)' do
      r = described_class.build(:dynamic, nil)
      expect(r.resolve(:any_key)).to be_nil
    end
  end

  describe '.build — invalid format' do
    it 'raises Error for unsupported format' do
      expect { described_class.build('bad', nil) }
        .to raise_error(ConsoleKit::Error, /unsupported tenants format/)
    end
  end
end
