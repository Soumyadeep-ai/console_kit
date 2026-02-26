# frozen_string_literal: true

require 'spec_helper'

# Dummy context class to use with verifying double
class DummyContext
  def tenant_shard; end
  def tenant_mongo_db; end
end

# Dummy handler classes outside `before` block to avoid leaky constant issues
class DummyHandlerA < ConsoleKit::Connections::BaseConnectionHandler
  def connect; end
  def available? = true
end

# Dummy handler classes outside `before` block to avoid leaky constant issues
class DummyHandlerB < ConsoleKit::Connections::BaseConnectionHandler
  def connect; end
  def available? = false
end

RSpec.describe ConsoleKit::Connections::ConnectionManager do
  let(:context) { instance_double(DummyContext) }

  before do
    stub_const('ConsoleKit::Connections::DummyHandlerA', DummyHandlerA)
    stub_const('ConsoleKit::Connections::DummyHandlerB', DummyHandlerB)
  end

  describe '.available_handlers' do
    subject(:handlers) { described_class.available_handlers(context) }

    it 'returns only instances of BaseConnectionHandler' do
      expect(handlers).to all(be_a(ConsoleKit::Connections::BaseConnectionHandler))
    end

    it 'includes available handlers' do
      expect(handlers.map(&:class)).to include(DummyHandlerA)
    end

    it 'excludes unavailable handlers' do
      expect(handlers.map(&:class)).not_to include(DummyHandlerB)
    end

    it 'passes the context to initialized handlers' do
      expect(handlers.first.context).to eq(context)
    end

    it 'returns an empty array if no handlers are available' do
      allow(ConsoleKit::Connections::BaseConnectionHandler).to receive(:registry).and_return([DummyHandlerB])
      expect(described_class.available_handlers(context)).to be_empty
    end
  end

  describe '.handler_classes' do
    it 'returns the classes from the BaseConnectionHandler registry' do
      expect(described_class.send(:handler_classes)).to eq(ConsoleKit::Connections::BaseConnectionHandler.registry)
    end
  end
end
