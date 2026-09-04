# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Connections::Dashboard do
  before do
    ConsoleKit::Diagnostics.clear_cache!
    allow(ConsoleKit::Output).to receive(:print_header)
    allow(ConsoleKit::Output).to receive(:print_warning)
    allow(ConsoleKit::Output).to receive(:print_raw)
  end

  describe '.display' do
    context 'when handlers have diagnostics' do
      let(:sql_diagnostics) do
        {
          name: 'SQL',
          status: :connected,
          latency_ms: 1.2,
          details: { adapter: 'PostgreSQL', pool_size: 5, version: 'PostgreSQL 14.0' }
        }
      end
      let(:mock_handler) { double(backend_key: :sql, safe_diagnostics: sql_diagnostics) }

      before do
        allow(ConsoleKit::Connections::ConnectionManager)
          .to receive(:available_handlers)
          .and_return([mock_handler])
      end

      it 'calls print_header with Connection Dashboard' do
        described_class.display
        expect(ConsoleKit::Output).to have_received(:print_header).with('Connection Dashboard')
      end

      it 'calls print_raw with a string' do
        described_class.display
        expect(ConsoleKit::Output).to have_received(:print_raw).with(kind_of(String))
      end

      it 'renders a table containing Unicode box-drawing characters', :aggregate_failures do
        described_class.display
        expect(ConsoleKit::Output).to have_received(:print_raw) do |output|
          expect(output).to match(/[┌─┐│├┤┼┬┴└┘]/)
        end
      end

      it 'does not call print_warning' do
        described_class.display
        expect(ConsoleKit::Output).not_to have_received(:print_warning)
      end
    end

    context 'when no connections are available' do
      before do
        allow(ConsoleKit::Connections::ConnectionManager)
          .to receive(:available_handlers)
          .and_return([])
      end

      it 'calls print_warning with No connections available' do
        described_class.display
        expect(ConsoleKit::Output).to have_received(:print_warning).with('No connections available')
      end

      it 'does not call print_header' do
        described_class.display
        expect(ConsoleKit::Output).not_to have_received(:print_header)
      end

      it 'does not call print_raw' do
        described_class.display
        expect(ConsoleKit::Output).not_to have_received(:print_raw)
      end
    end

    context 'with mixed statuses' do
      let(:connected_diagnostics) do
        { name: 'SQL', status: :connected, latency_ms: 1.2, details: { adapter: 'PostgreSQL' } }
      end
      let(:error_diagnostics) do
        { name: 'MongoDB', status: :error, latency_ms: nil, details: { error: 'auth failed' } }
      end
      let(:connected_handler) { double(backend_key: :sql, safe_diagnostics: connected_diagnostics) }
      let(:error_handler)     { double(backend_key: :mongo, safe_diagnostics: error_diagnostics) }

      before do
        allow(ConsoleKit::Connections::ConnectionManager)
          .to receive(:available_handlers)
          .and_return([connected_handler, error_handler])
      end

      it 'renders a table containing the connected checkmark', :aggregate_failures do
        described_class.display
        expect(ConsoleKit::Output).to have_received(:print_raw) do |output|
          expect(output).to include("\u2713")
        end
      end

      it 'renders a table containing the error cross', :aggregate_failures do
        described_class.display
        expect(ConsoleKit::Output).to have_received(:print_raw) do |output|
          expect(output).to include("\u2717")
        end
      end

      it 'renders a table containing both service names', :aggregate_failures do
        described_class.display
        expect(ConsoleKit::Output).to have_received(:print_raw) do |output|
          expect(output).to include('SQL')
          expect(output).to include('MongoDB')
        end
      end
    end

    context 'with unavailable status' do
      let(:unavailable_diagnostics) do
        { name: 'Redis', status: :unavailable, latency_ms: nil, details: {} }
      end
      let(:mock_handler) { double(backend_key: :redis, safe_diagnostics: unavailable_diagnostics) }

      before do
        allow(ConsoleKit::Connections::ConnectionManager)
          .to receive(:available_handlers)
          .and_return([mock_handler])
      end

      it 'renders the N/A dash character for unavailable status', :aggregate_failures do
        described_class.display
        expect(ConsoleKit::Output).to have_received(:print_raw) do |output|
          expect(output).to include("\u2014 N/A")
        end
      end
    end

    context 'with diagnostic levels' do
      let(:row) { { name: 'Redis', status: :connected, latency_ms: nil, details: {} } }
      let(:mock_handler) { double(backend_key: :redis, safe_diagnostics: row) }

      before do
        allow(ConsoleKit::Connections::ConnectionManager)
          .to receive(:available_handlers)
          .and_return([mock_handler])
      end

      it 'asks for the cheap basic level by default' do
        described_class.display
        expect(mock_handler).to have_received(:safe_diagnostics).with(hash_including(level: :basic))
      end

      it 'passes an explicit level through to the handler' do
        described_class.display(level: :full)
        expect(mock_handler).to have_received(:safe_diagnostics).with(hash_including(level: :full))
      end

      it 'rejects an unknown level' do
        expect { described_class.display(level: :deep) }.to raise_error(ConsoleKit::ConfigurationError, /:deep/)
      end
    end
  end
end
