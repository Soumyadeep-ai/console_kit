# spec/console_kit/steps/tenant_configurator_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Steps::TenantConfigurator do
  subject(:step) { described_class.new(ctx) }

  let(:config) { ConsoleKit.configuration }
  let(:context_class) do
    Class.new do
      class << self
        attr_accessor :partner_code, :shard
      end
    end
  end
  let(:ctx) { ConsoleKit::PipelineContext.new(config: config) }

  before do
    stub_const('FakeContext', context_class)
    ConsoleKit.configure do |c|
      c.tenants = {
        tenant_a: { constants: { partner_code: 'pa', shard: 'shard_01' } }
      }
      c.context_class = 'FakeContext'
    end
    ctx.resolved_tenant = :tenant_a
  end

  it 'returns success when configuration succeeds' do
    allow(ConsoleKit::Connections::ConnectionManager).to receive(:available_handlers).and_return([])
    expect(step.call.success?).to be true
  end

  it 'marks Context as configured on success' do
    allow(ConsoleKit::Connections::ConnectionManager).to receive(:available_handlers).and_return([])
    step.call
    expect(ConsoleKit::Context.current.configured?).to be true
  end

  it 'returns failure when tenant constants missing' do
    ctx.resolved_tenant = :nonexistent
    expect(step.call.failure?).to be true
  end

  context 'when required keys are missing from constants' do
    before do
      ConsoleKit.configure do |c|
        c.tenants = { tenant_a: { constants: { partner_code: 'pa' } } }
        c.context_class = 'FakeContext'
        c.required_tenant_keys = %i[shard partner_code]
      end
      ctx.resolved_tenant = :tenant_a
    end

    it 'returns failure' do
      expect(step.call.failure?).to be true
    end
  end

  context 'when connection handlers are available' do
    let(:handler_class) do
      Class.new do
        attr_reader :connected

        def connect
          @connected = true
        end
      end
    end
    let(:handler) { handler_class.new }

    before do
      allow(ConsoleKit::Connections::ConnectionManager)
        .to receive(:available_handlers).and_return([handler])
    end

    it 'calls connect on each handler' do
      step.call
      expect(handler.connected).to be true
    end
  end

  it 'returns failure when an unexpected error occurs during configuration' do
    allow(ConsoleKit::Connections::ConnectionManager)
      .to receive(:available_handlers).and_raise(RuntimeError, 'db gone')
    result = step.call
    expect(result.failure?).to be true
  end

  it 'includes the error message in the failure' do
    allow(ConsoleKit::Connections::ConnectionManager)
      .to receive(:available_handlers).and_raise(RuntimeError, 'db gone')
    result = step.call
    expect(result.error).to include('db gone')
  end

  context 'when existing value differs only in case' do
    before do
      context_class.partner_code = 'PA'
      ConsoleKit.configure do |c|
        c.tenants = { tenant_a: { constants: { partner_code: 'pa', shard: 'shard_01' } } }
        c.context_class = 'FakeContext'
        c.context_field_mapping = { partner_code: :partner_code, shard: :shard }
      end
      allow(ConsoleKit::Connections::ConnectionManager).to receive(:available_handlers).and_return([])
      allow(ConsoleKit::Output).to receive(:print_warning)
    end

    it 'warns about case mismatch' do
      step.call
      expect(ConsoleKit::Output).to have_received(:print_warning)
        .with(a_string_including('case mismatch'))
    end
  end
end
