# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Connections::TableFormatter do
  describe '.format_status' do
    it 'returns connected string for :connected' do
      expect(described_class.format_status(:connected)).to include('Connected')
    end

    it 'returns error string for :error' do
      expect(described_class.format_status(:error)).to include('Error')
    end

    it 'returns error string for :timeout' do
      expect(described_class.format_status(:timeout)).to include('Error')
    end

    it 'returns N/A string for :unavailable' do
      expect(described_class.format_status(:unavailable)).to include('N/A')
    end

    it 'returns unknown string for unrecognized status' do
      expect(described_class.format_status(:something_weird)).to eq('? Unknown')
    end
  end

  describe '.format_latency' do
    it 'returns ms string when latency_ms is given' do
      expect(described_class.format_latency(12.5)).to eq('12.5ms')
    end

    it 'returns dash when latency_ms is nil' do
      expect(described_class.format_latency(nil)).to eq("—")
    end
  end

  describe '.format_details' do
    it 'returns empty string when details is nil' do
      expect(described_class.format_details(nil)).to eq('')
    end

    it 'returns empty string when details is empty hash' do
      expect(described_class.format_details({})).to eq('')
    end

    it 'formats key-value pairs' do
      expect(described_class.format_details({ adapter: 'PostgreSQL' })).to include('adapter: PostgreSQL')
    end

    it 'compacts nil values' do
      expect(described_class.format_details({ a: 'x', b: nil })).not_to include('b:')
    end
  end

  describe '.format_row' do
    it 'returns an array of 4 elements' do
      diag = { name: 'SQL', status: :connected, latency_ms: 1.0, details: { adapter: 'PG' } }
      expect(described_class.format_row(diag).length).to eq(4)
    end
  end
end

RSpec.describe ConsoleKit::Connections::Dashboard do
  before do
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
      let(:mock_handler) { double(safe_diagnostics: sql_diagnostics) }

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
      let(:connected_handler) { double(safe_diagnostics: connected_diagnostics) }
      let(:error_handler)     { double(safe_diagnostics: error_diagnostics) }

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
      let(:mock_handler) { double(safe_diagnostics: unavailable_diagnostics) }

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
  end
end
