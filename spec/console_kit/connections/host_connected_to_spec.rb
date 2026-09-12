# frozen_string_literal: true

require 'spec_helper'

# Rails' `connected_to` pops the shard stack in an `ensure`, by POSITION rather
# than by identity: it removes whatever frame is on top when the block exits.
# A tenant switch committed inside such a block used to push its frame on top of
# the block's, so the block destroyed ConsoleKit's frame on the way out and left
# the block's own shard live underneath ConsoleKit's committed tenant - every
# query after that ran against another tenant's database, silently, until
# somebody happened to call `verify_tenant!`.
module HostConnectedTo
end

RSpec.describe HostConnectedTo do
  include_context 'with a four-backend tenant setup'

  let(:stack) { base_class.connected_to_stack }

  # Attempts the inner switch inside a host block pinned to another shard, and
  # hands back whatever the switch raised.
  def switch_inside_host_block(tenant = 'initech')
    base_class.connected_to(shard: :shard_globex) { failed_switch(tenant) }
  end

  describe 'a committed switch attempted inside a host connected_to block' do
    before { ConsoleKit.switch_tenant('acme') }

    it 'refuses the switch instead of committing one the block will undo' do
      expect(switch_inside_host_block).to be_a(ConsoleKit::TenantSwitchError)
    end

    it 'says the shard it asked for is not the shard that is live' do
      expect(switch_inside_host_block.original_error).to be_a(ConsoleKit::ConnectionVerificationError)
    end

    it 'leaves the enclosing tenant current' do
      switch_inside_host_block
      expect(ConsoleKit.current_tenant).to eq('acme')
    end

    it 'leaves that tenant shard live once the block has exited' do
      switch_inside_host_block
      expect(base_class.current_shard).to eq(:shard_acme)
    end

    it 'leaves every other backend on the enclosing tenant too' do
      switch_inside_host_block
      expect(identities).to eq(expected_identities('acme'))
    end

    it 'can still prove the tenant afterwards' do
      switch_inside_host_block
      expect { ConsoleKit.verify_tenant! }.not_to raise_error
    end

    it 'gives the block back its own frame to pop' do
      switch_inside_host_block
      expect(stack.size).to eq(1)
    end
  end

  # The frame is replaced where it already sits rather than re-pushed, so
  # neither repeated switches nor repeated host blocks can grow the stack Rails
  # walks on every query.
  describe 'host blocks repeated across a console session' do
    before { ConsoleKit.switch_tenant('acme') }

    it 'holds the stack at one ConsoleKit frame across five of them' do
      5.times { switch_inside_host_block }
      expect(stack.size).to eq(1)
    end

    it 'keeps the committed tenant and the live shard in step' do
      5.times { switch_inside_host_block }
      expect([ConsoleKit.current_tenant, base_class.current_shard]).to eq(['acme', :shard_acme])
    end

    it 'keeps holding it while tenants are switched between blocks' do
      %w[globex acme initech].each do |tenant|
        ConsoleKit.switch_tenant(tenant)
        switch_inside_host_block
      end
      expect(stack.size).to eq(1)
    end
  end

  # ConsoleKit owns no frame yet, so this switch has to push one - on top of the
  # host's, which is exactly where the block's `ensure` will destroy it. It
  # cannot be prevented, only noticed: the next thing ConsoleKit is asked puts
  # the frame back rather than reporting a tenant whose shard is not live.
  describe 'a first switch made inside a host connected_to block' do
    before { base_class.connected_to(shard: :shard_globex) { ConsoleKit.switch_tenant('initech') } }

    it 'puts the committed shard back rather than reporting one that is not live' do
      ConsoleKit.verify_tenant!
      expect(base_class.current_shard).to eq(:shard_initech)
    end

    it 'verifies the tenant it committed' do
      expect(ConsoleKit.verify_tenant!.tenant_key).to eq('initech')
    end

    it 'counts the frame it had to re-assert' do
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Instrumentation.counts['console_kit.sql_frame_reasserted']).to eq(1)
    end

    it 'says so rather than healing silently' do
      allow(ConsoleKit::Output).to receive(:print_warning)
      ConsoleKit.verify_tenant!
      expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('connected_to'))
    end
  end

  # Rails keeps `connected_to_stack` per THREAD - 6.1 and 7.0 through thread
  # variables, 7.1+ through IsolatedExecutionState at its default :thread
  # isolation. ConsoleKit's record of its own frame was fiber-local, so inside
  # any Fiber or Enumerator it could not see the frame it owns and pushed a
  # second one that nothing would ever replace, pop or account for.
  describe 'a switch made inside a Fiber' do
    let(:shared_stack) { [] }

    before do
      allow(base_class).to receive(:connected_to_stack).and_return(shared_stack)
      ConsoleKit.switch_tenant('acme')
      Fiber.new { ConsoleKit.switch_tenant('globex') }.resume
    end

    it 'replaces the frame it already owns instead of pushing a second one' do
      expect(shared_stack.size).to eq(1)
    end

    it 'lands on the shard the fiber asked for' do
      expect(base_class.current_shard).to eq(:shard_globex)
    end
  end

  # A properly nested scope is popped by ConsoleKit itself before the host block
  # closes, so it keeps Rails' own semantics: the innermost frame wins, and the
  # host's shard is live again the moment the scope exits.
  describe 'a with_tenant scope nested inside a host connected_to block' do
    it 'applies the scoped tenant inside the block' do
      inner = base_class.connected_to(shard: :shard_globex) do
        ConsoleKit.with_tenant('acme') { base_class.current_shard }
      end
      expect(inner).to eq(:shard_acme)
    end

    it 'gives the host block its shard back when the scope exits' do
      inner = base_class.connected_to(shard: :shard_globex) do
        ConsoleKit.with_tenant('acme') { nil }
        base_class.current_shard
      end
      expect(inner).to eq(:shard_globex)
    end

    it 'leaves no residue behind once the block exits' do
      base_class.connected_to(shard: :shard_globex) { ConsoleKit.with_tenant('acme') { nil } }
      expect(stack).to be_empty
    end
  end
end
