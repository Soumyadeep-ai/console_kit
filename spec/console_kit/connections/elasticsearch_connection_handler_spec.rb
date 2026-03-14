# frozen_string_literal: true

require 'spec_helper'

# Dummy context object for connection handler specs
class DummyContext
  attr_reader :tenant_elasticsearch_prefix

  def initialize(tenant_elasticsearch_prefix: nil)
    @tenant_elasticsearch_prefix = tenant_elasticsearch_prefix
  end
end

RSpec.describe ConsoleKit::Connections::ElasticsearchConnectionHandler do
  let(:context) { instance_double(DummyContext, tenant_elasticsearch_prefix: 'acme') }
  let(:handler) { described_class.new(context) }

  before do
    stub_const('Elasticsearch', Module.new)
  end

  after do
    Thread.current[:console_kit_elasticsearch_prefix] = nil
  end

  describe '#connect' do
    it 'sets the thread-local prefix' do
      handler.connect
      expect(Thread.current[:console_kit_elasticsearch_prefix]).to eq('acme')
    end

    context 'when Elasticsearch::Model is defined' do
      before do
        es_model = Module.new do
          class << self
            attr_accessor :index_name_prefix
          end
        end
        stub_const('Elasticsearch::Model', es_model)
      end

      it 'sets index_name_prefix on Elasticsearch::Model' do
        handler.connect
        expect(Elasticsearch::Model.index_name_prefix).to eq('acme')
      end
    end

    context 'when tenant_elasticsearch_prefix is empty' do
      let(:context) { instance_double(DummyContext, tenant_elasticsearch_prefix: '') }

      it 'sets thread-local prefix to nil' do
        handler.connect
        expect(Thread.current[:console_kit_elasticsearch_prefix]).to be_nil
      end
    end

    context 'when tenant_elasticsearch_prefix is nil' do
      let(:context) { instance_double(DummyContext, tenant_elasticsearch_prefix: nil) }

      it 'sets thread-local prefix to nil' do
        handler.connect
        expect(Thread.current[:console_kit_elasticsearch_prefix]).to be_nil
      end
    end
  end

  describe '#available?' do
    it 'returns true when Elasticsearch is defined' do
      expect(handler).to be_available
    end

    it 'returns false when Elasticsearch is not defined' do
      hide_const('Elasticsearch')
      expect(handler).not_to be_available
    end
  end

  describe 'context attribute access' do
    it 'reads tenant_elasticsearch_prefix from context' do
      expect(handler.send(:context_attribute, :tenant_elasticsearch_prefix)).to eq('acme')
    end
  end
end
