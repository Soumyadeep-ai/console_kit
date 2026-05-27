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

    it 'returns all change tuples' do
      result = wrapper.assign(constants, mapping)
      expect(result).to include([:tenant_shard, nil, 'shard_acme'])
    end

    context 'when previous value differs only in case' do
      before { ctx.partner_identifier = 'ACME' }

      let(:constants) { { shard: 'shard_acme', partner_code: 'acme' } }

      it 'includes the mismatch in returned tuples' do
        result = wrapper.assign(constants, mapping)
        expect(result).to include([:partner_identifier, 'ACME', 'acme'])
      end

      it 'still assigns the configured value' do
        wrapper.assign(constants, mapping)
        expect(ctx.partner_identifier).to eq('acme')
      end
    end

    context 'when previous value matches exactly' do
      before { ctx.partner_identifier = 'ACME' }

      it 'does not include it as a case mismatch tuple' do
        result = wrapper.assign(constants, mapping)
        expect(result).to include([:partner_identifier, 'ACME', 'ACME'])
      end
    end

    context 'when values differ in more than case' do
      before { ctx.partner_identifier = 'OTHER' }

      it 'includes the change tuple but not as a case-only mismatch' do
        result = wrapper.assign(constants, mapping)
        expect(result).to include([:partner_identifier, 'OTHER', 'ACME'])
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

    context 'when handler is not available' do
      let(:ctx_class) do
        Class.new do
          class << self
            attr_accessor :tenant_mongo_db
          end
        end
      end

      before { hide_const('Mongoid') }

      it 'skips the handler attribute when handler is unavailable' do
        expect(described_class.for_context(ctx_class).attributes).not_to include(:tenant_mongo_db)
      end
    end

    context 'when handler_available? raises StandardError' do
      let(:bad_handler) do
        Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
          def available?
            raise StandardError, 'unexpected'
          end
        end
      end

      it 'returns false and skips' do
        expect(described_class.send(:handler_available?, bad_handler)).to be(false)
      end
    end
  end

  describe '#assign when safe_read raises' do
    let(:ctx) do
      obj = Object.new
      obj.define_singleton_method(:tenant_shard) { raise StandardError, 'read error' }
      obj.define_singleton_method(:tenant_shard=) { |_v| }
      obj
    end
    let(:attrs) { [:tenant_shard] }
    let(:wrapper) { described_class.new(ctx, attrs) }

    it 'returns nil as existing value' do
      result = wrapper.assign({ shard: 'x' }, { tenant_shard: :shard })
      expect(result.first[1]).to be_nil
    end
  end
end
