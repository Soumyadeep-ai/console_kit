# spec/console_kit/doctor/checks/adapter_supported.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::Checks::AdapterSupported do
  subject(:check) { described_class.new(config) }

  let(:config) { ConsoleKit.configuration }

  context 'when ActiveRecord is not loaded' do
    before { hide_const('ActiveRecord::Base') }

    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end

    it 'returns not-loaded message' do
      expect(check.call.message).to eq('ActiveRecord not loaded')
    end
  end

  context 'when ActiveRecord is loaded' do
    let(:db_config) { double('db_config') } # rubocop:disable RSpec/VerifiedDoubles

    before do
      stub_const('ActiveRecord::Base', Class.new)
      allow(ActiveRecord::Base).to receive(:connection_db_config).and_return(db_config)
    end

    context 'when adapter detection raises' do
      before { allow(db_config).to receive(:adapter).and_raise(StandardError) }

      it 'returns ok status' do
        expect(check.call.status).to eq(:ok)
      end

      it 'returns could not detect message' do
        expect(check.call.message).to eq('could not detect adapter')
      end
    end

    context 'when adapter is supported' do
      before { allow(db_config).to receive(:adapter).and_return('postgresql') }

      it 'returns ok status' do
        expect(check.call.status).to eq(:ok)
      end

      it 'names the adapter in the message' do
        expect(check.call.message).to include('postgresql')
      end
    end

    context 'when adapter is unsupported' do
      before { allow(db_config).to receive(:adapter).and_return('oracle') }

      it 'returns warn status' do
        expect(check.call.status).to eq(:warn)
      end

      it 'names the adapter in the message' do
        expect(check.call.message).to include('oracle')
      end
    end
  end
end
