# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::Checks::AuditLogPathWritable do
  subject(:check) { described_class.new(config) }

  let(:config) { ConsoleKit.configuration }

  context 'when audit logging is disabled' do
    before { config.audit_log = false }

    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end

    it 'message includes disabled' do
      expect(check.call.message).to include('disabled')
    end
  end

  context 'when enabled and path directory is writable' do
    before do
      config.audit_log      = true
      config.audit_log_path = '/tmp/audit.log'
      allow(File).to receive(:writable?).with('/tmp').and_return(true)
    end

    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end

    it 'includes path in message' do
      expect(check.call.message).to include('/tmp/audit.log')
    end
  end

  context 'when enabled and path directory is not writable' do
    before do
      config.audit_log      = true
      config.audit_log_path = '/root/audit.log'
      allow(File).to receive(:writable?).with('/root').and_return(false)
    end

    it 'returns warn status' do
      expect(check.call.status).to eq(:warn)
    end

    it 'includes path in message' do
      expect(check.call.message).to include('/root/audit.log')
    end
  end
end
