# frozen_string_literal: true

require_relative 'tenant_backends'

# A fully wired ConsoleKit: three tenants, four live backends and a context
# object, so a whole `switch_tenant` can be driven end to end and every
# observable identity read back afterwards.
RSpec.shared_context 'with a four-backend tenant setup' do
  let(:base_class) { TenantBackends.sharded_base }
  let(:context_class) { TenantBackends.shared_context_class }

  before do
    ConsoleKit.configure do |config|
      config.tenants = TenantBackends::TENANTS
      config.context_class = context_class
      config.pretty_output = false
    end
    stub_const('ApplicationRecord', base_class)
    stub_const('Mongoid', TenantBackends::ThreadedMongoid)
    Redis.current = TenantBackends::CountingRedis.new
    ConsoleKit::Output.silent = true
  end

  after { TenantBackends.reset! }

  # --- observable state ------------------------------------------------

  def identities = TenantBackends.live_identities(base_class)
  def context_values = TenantBackends.live_context(context_class)
  def expected_identities(key) = TenantBackends.expected_identities(key)
  def expected_context(key) = TenantBackends.expected_context(key)

  # Everything an observer can see about "which tenant is this process on".
  def observable_state
    { tenant: ConsoleKit.current_tenant, context: context_values, identities: identities }
  end

  def expected_state(key)
    { tenant: key, context: expected_context(key), identities: expected_identities(key) }
  end

  # --- driving ---------------------------------------------------------

  # Switches and hands back the error instead of raising, so an example can
  # assert on the state the failure left behind.
  def failed_switch(key)
    ConsoleKit.switch_tenant(key)
    nil
  rescue StandardError => e
    e
  end

  # Runs `block` on a fresh thread with ConsoleKit's per-thread output silenced.
  def tenant_thread(&block)
    Thread.new do
      ConsoleKit::Output.silent = true
      block.call
    end
  end
end
