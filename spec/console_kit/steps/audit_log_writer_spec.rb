# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Steps::AuditLogWriter do
  subject(:step) { described_class.new(ctx) }

  let(:config) { ConsoleKit.configuration }
  let(:ctx)    { ConsoleKit::PipelineContext.new(config: config) }

  before do
    ConsoleKit.configure do |c|
      c.tenants       = { tenant_a: { constants: { shard: 's1', partner_code: 'pa' } } }
      c.context_class = 'Object'
    end
    ctx.resolved_tenant = :tenant_a
  end

  context 'when audit_log is false' do
    before { config.audit_log = false }

    it 'returns success' do
      expect(step.call.success?).to be true
    end

    it 'does not instantiate AuditLogger' do
      allow(ConsoleKit::AuditLogger).to receive(:new)
      step.call
      expect(ConsoleKit::AuditLogger).not_to have_received(:new)
    end
  end

  context 'when audit_log is true' do
    let(:mock_logger) { instance_double(ConsoleKit::AuditLogger, log: nil) }

    before do
      config.audit_log      = true
      config.audit_log_path = '/tmp/test_audit.log'
      allow(ConsoleKit::AuditLogger).to receive(:new).and_return(mock_logger)
    end

    it 'returns success' do
      expect(step.call.success?).to be true
    end

    it 'instantiates logger with configured path' do
      step.call
      expect(ConsoleKit::AuditLogger).to have_received(:new).with('/tmp/test_audit.log')
    end

    it 'logs tenant_switch action with success status' do
      step.call
      expect(mock_logger).to have_received(:log)
        .with(tenant: :tenant_a, action: :tenant_switch, status: :success)
    end
  end
end
