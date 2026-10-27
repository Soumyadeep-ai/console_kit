# frozen_string_literal: true

require 'spec_helper'

# Switching from a configured tenant to one whose switch fails must leave the console on the
# previous tenant: no banner, no prompt label for the failed tenant, backends untouched.
RSpec.describe ConsoleKit::TenantOrchestrator do
  include_context 'with a four-backend tenant setup'

  let(:tenants) do
    TenantBackends::TENANTS.merge(
      'umbrella' => { constants: { shard: 'shard_unregistered', mongo_db: 'umbrella_db', partner_code: 'UMB' } }
    )
  end

  let(:reset_output) do
    ConsoleKit::Output.silent = false
    output = StringIO.new
    $stdout = output
    described_class.reset
    output.string
  ensure
    $stdout = STDOUT
    ConsoleKit::Output.silent = true
  end

  before do
    ConsoleKit.configuration.tenants = tenants
    described_class.current_tenant = nil
    ConsoleKit::TenantConfigurator.configure_tenant('acme')
    described_class.current_tenant = 'acme'
    allow($stdin).to receive_messages(tty?: true, gets: "umbrella\n")
  end

  it 'reports why the switch failed' do
    expect(reset_output).to include("Failed to configure tenant 'umbrella'")
  end

  it 'does not announce the failed tenant' do
    expect(reset_output).not_to include('Tenant initialized: umbrella')
  end

  it 'keeps the previous tenant current' do
    reset_output
    expect(described_class.current_tenant).to eq('acme')
  end

  it 'keeps the previous tenant configured' do
    reset_output
    expect(ConsoleKit::StateStore.configured?).to be(true)
  end

  it 'leaves every backend on the previous tenant' do
    reset_output
    expect(identities).to eq(expected_identities('acme'))
  end
end
