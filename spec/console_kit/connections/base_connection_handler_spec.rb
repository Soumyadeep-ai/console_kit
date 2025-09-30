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

  describe '#connect' do
    it 'raises NotImplementedError' do
      expect { handler.connect }.to raise_error(NotImplementedError)
    end
  end

  describe '#available?' do
    it 'returns false by default' do
      expect(handler.available?).to be(false)
    end
  end
end
