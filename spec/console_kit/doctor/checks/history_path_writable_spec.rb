# spec/console_kit/doctor/checks/history_path_writable_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::Checks::HistoryPathWritable do
  subject(:check) { described_class.new(config) }

  let(:config) { ConsoleKit.configuration }

  context 'when the history directory is writable' do
    before do
      config.recent_tenant_history_path = '/tmp/.console_kit_history'
      allow(File).to receive(:writable?).with('/tmp').and_return(true)
    end

    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end

    it 'includes the path in the message' do
      expect(check.call.message).to include('/tmp/.console_kit_history')
    end
  end

  context 'when the history directory is not writable' do
    before do
      config.recent_tenant_history_path = '/root/.console_kit_history'
      allow(File).to receive(:writable?).with('/root').and_return(false)
    end

    it 'returns warn status' do
      expect(check.call.status).to eq(:warn)
    end

    it 'includes the path in the message' do
      expect(check.call.message).to include('/root/.console_kit_history')
    end
  end
end
