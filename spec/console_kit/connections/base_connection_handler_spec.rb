# frozen_string_literal: true

require 'spec_helper'

# Dummy context object for connection handler specs
class DummyContext
  attr_reader :tenant_shard, :tenant_mongo_db, :partner_identifier

  def initialize(tenant_shard: nil, tenant_mongo_db: nil, partner_identifier: nil)
    @tenant_shard = tenant_shard
    @tenant_mongo_db = tenant_mongo_db
    @partner_identifier = partner_identifier
  end
end

RSpec.describe ConsoleKit::Connections::BaseConnectionHandler do
  let(:context) { instance_double(DummyContext) }
  let(:handler) { described_class.new(context) }

  describe '.registry' do
    it 'includes its subclasses' do
      subclass = Class.new(described_class)
      expect(described_class.registry).to include(subclass)
    end
  end

  describe '#connect' do
    it 'raises NotImplementedError' do
      expect { handler.connect }.to raise_error(NotImplementedError)
    end

    it 'includes the class name in the error message' do
      expect { handler.connect }.to raise_error(NotImplementedError, /BaseConnectionHandler must implement #connect/)
    end
  end

  describe '#available?' do
    it 'returns false by default' do
      expect(handler.available?).to be(false)
    end
  end

  describe 'initialization' do
    it 'assigns the context' do
      expect(handler.context).to eq(context)
    end
  end

  describe 'subclassing behavior' do
    it 'registers subclasses automatically upon definition' do
      new_handler = Class.new(described_class)
      expect(described_class.registry).to include(new_handler)
    end

    it 'preserves the order of registration' do
      # NOTE: registry is a class instance variable
      count = described_class.registry.size
      sub1 = Class.new(described_class)
      sub2 = Class.new(described_class)
      expect(described_class.registry[count..(count + 1)]).to eq([sub1, sub2])
    end
  end
end
