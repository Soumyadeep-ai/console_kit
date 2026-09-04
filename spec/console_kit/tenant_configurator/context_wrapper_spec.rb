# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::TenantConfigurator::ContextWrapper do
  let(:ctx) do
    Struct.new(:tenant_shard, :partner_identifier, :tenant_mongo_db).new
  end
  let(:attributes) { %i[tenant_shard partner_identifier] }
  let(:wrapper) { described_class.new(ctx, attributes) }

  describe '#assign' do
    let(:mapping) { { tenant_shard: :shard, partner_identifier: :partner_code } }
    let(:constants) { { shard: 'shard_acme', partner_code: 'ACME' } }

    it 'sets attribute values on context' do
      wrapper.assign(constants, mapping)
      expect(ctx.tenant_shard).to eq('shard_acme')
    end

    it 'returns a hash of the assigned values' do
      result = wrapper.assign(constants, mapping)
      expect(result).to eq(tenant_shard: 'shard_acme', partner_identifier: 'ACME')
    end

    context 'when previous value differs only in case' do
      before { ctx.partner_identifier = 'ACME' }

      let(:constants) { { shard: 'shard_acme', partner_code: 'acme' } }

      it 'warns about the case mismatch' do
        allow(ConsoleKit::Output).to receive(:print_warning)
        wrapper.assign(constants, mapping)
        expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('ACME', 'acme'))
      end

      it 'still assigns the configured value' do
        wrapper.assign(constants, mapping)
        expect(ctx.partner_identifier).to eq('acme')
      end
    end

    context 'when previous value matches exactly' do
      before { ctx.partner_identifier = 'ACME' }

      it 'does not warn about a case mismatch' do
        allow(ConsoleKit::Output).to receive(:print_warning)
        wrapper.assign(constants, mapping)
        expect(ConsoleKit::Output).not_to have_received(:print_warning)
      end
    end

    context 'when values differ in more than case' do
      before { ctx.partner_identifier = 'OTHER' }

      it 'assigns the new value' do
        result = wrapper.assign(constants, mapping)
        expect(result[:partner_identifier]).to eq('ACME')
      end

      it 'does not warn about a case mismatch' do
        allow(ConsoleKit::Output).to receive(:print_warning)
        wrapper.assign(constants, mapping)
        expect(ConsoleKit::Output).not_to have_received(:print_warning)
      end
    end
  end

  describe '#reset' do
    before do
      ctx.tenant_shard = 'some_shard'
      ctx.partner_identifier = 'ACME'
    end

    it 'clears all tracked attributes' do
      wrapper.reset
      expect(ctx.tenant_shard).to be_nil
    end

    it 'clears partner_identifier' do
      wrapper.reset
      expect(ctx.partner_identifier).to be_nil
    end
  end

  describe '#any_set?' do
    it 'returns false when no attributes set' do
      expect(wrapper).not_to be_any_set
    end

    it 'returns true when at least one attribute set' do
      ctx.tenant_shard = 'shard_x'
      expect(wrapper).to be_any_set
    end
  end

  describe '.for_context' do
    let(:ctx_class) do
      Class.new do
        class << self
          attr_accessor :partner_identifier, :tenant_shard
        end
      end
    end

    it 'returns a ContextWrapper for the given context' do
      w = described_class.for_context(ctx_class)
      expect(w).to be_a(described_class)
    end

    it 'detects partner_identifier when setter exists' do
      w = described_class.for_context(ctx_class)
      expect(w.attributes).to include(:partner_identifier)
    end

    context 'when context lacks partner_identifier setter' do
      let(:ctx_class) do
        Class.new { class << self; attr_accessor :tenant_shard; end }
      end

      it 'skips partner_identifier' do
        expect(described_class.for_context(ctx_class).attributes).not_to include(:partner_identifier)
      end
    end
  end

  describe 'an attribute whose getter raises' do
    let(:ctx) do
      Class.new do
        class << self
          attr_accessor :tenant_shard
          attr_writer :partner_identifier

          def partner_identifier = raise(IOError, 'context store not initialized')
        end
      end
    end

    before do
      allow(ConsoleKit::Output).to receive(:print_warning)
      ctx.tenant_shard = 'shard_acme'
      ctx.partner_identifier = 'ACME'
    end

    it 'records a sentinel rather than nil, so rollback cannot silently destroy the value' do
      expect(wrapper.current_values[:partner_identifier]).to eq(described_class::UNREADABLE)
    end

    it 'still records the attributes it could read' do
      expect(wrapper.current_values[:tenant_shard]).to eq('shard_acme')
    end

    it 'warns that the attribute will not be restorable' do
      wrapper.current_values
      expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('partner_identifier'))
    end

    context 'when that snapshot is restored' do
      let(:snapshot) { wrapper.current_values }

      before do
        snapshot
        ctx.tenant_shard = 'shard_globex'
        ctx.partner_identifier = 'GLOBEX'
      end

      it 'reports the failure instead of claiming a clean rollback' do
        expect { wrapper.restore(snapshot) }.to raise_error(ConsoleKit::Error, /partner_identifier/)
      end

      it 'does not write the sentinel onto the context' do
        wrapper.restore(snapshot)
      rescue ConsoleKit::Error
        expect(ctx.instance_variable_get(:@partner_identifier)).to eq('GLOBEX')
      end

      it 'still restores every attribute it could read' do
        wrapper.restore(snapshot)
      rescue ConsoleKit::Error
        expect(ctx.tenant_shard).to eq('shard_acme')
      end
    end
  end
end
