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
  end
end
