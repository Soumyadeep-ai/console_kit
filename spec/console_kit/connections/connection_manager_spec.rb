# spec/console_kit/connections/connection_manager_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Connections::ConnectionManager do
  describe '.available_handlers' do
    let(:context_class) { instance_double(Object) }

    let(:available_handler_class) do
      Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
        def available? = true
        def connect    = nil
        def diagnostics = {}
      end
    end

    let(:unavailable_handler_class) do
      Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
        def available? = false
        def connect    = nil
        def diagnostics = {}
      end
    end

    before do
      allow(ConsoleKit::Connections::BaseConnectionHandler)
        .to receive(:registry)
        .and_return([available_handler_class, unavailable_handler_class])
    end

    it 'returns handlers whose available? returns true' do
      result = described_class.available_handlers(context_class)
      expect(result.map(&:class)).to eq([available_handler_class])
    end

    it 'returns empty array when no handlers are available' do
      allow(ConsoleKit::Connections::BaseConnectionHandler).to receive(:registry).and_return([])
      expect(described_class.available_handlers(context_class)).to eq([])
    end

    it 'passes context_class to each handler constructor' do
      handler = described_class.available_handlers(context_class).first
      expect(handler.context).to eq(context_class)
    end
  end
end
