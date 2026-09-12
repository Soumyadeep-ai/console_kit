# frozen_string_literal: true

require 'spec_helper'

# `with_tenant` is the only API that promises to put the *enclosing* tenant back
# rather than the default one, so every exit route out of the block has to be
# checked: falling off the end, raising, and an inner switch that never
# committed at all.
module NestedTenant
end

RSpec.describe NestedTenant do
  include_context 'with a four-backend tenant setup'

  describe 'a scope nested inside another scope' do
    let(:trace) { trace_two_levels }

    it 'is completely on the outer tenant inside the outer block' do
      expect(trace[:outer]).to eq(expected_state('acme'))
    end

    it 'is completely on the inner tenant inside the inner block' do
      expect(trace[:inner]).to eq(expected_state('globex'))
    end

    it 'is back on the outer tenant once the inner block returns' do
      expect(trace[:after_inner]).to eq(expected_state('acme'))
    end

    it 'is back on the original state once the outer block returns' do
      expect(trace[:after_outer]).to eq(expected_state(nil))
    end

    def trace_two_levels
      seen = {}
      ConsoleKit.with_tenant('acme') do
        seen[:outer] = observable_state
        ConsoleKit.with_tenant('globex') { seen[:inner] = observable_state }
        seen[:after_inner] = observable_state
      end
      seen.merge(after_outer: observable_state)
    end
  end

  describe 'three levels of nesting' do
    let(:trace) { trace_three_levels }

    it 'reaches the innermost tenant completely' do
      expect(trace[:third]).to eq(expected_state('initech'))
    end

    it 'unwinds to the second tenant' do
      expect(trace[:back_to_second]).to eq(expected_state('globex'))
    end

    it 'unwinds to the first tenant' do
      expect(trace[:back_to_first]).to eq(expected_state('acme'))
    end

    it 'unwinds to the original state' do
      expect(trace[:back_to_start]).to eq(expected_state(nil))
    end

    def trace_three_levels
      seen = {}
      ConsoleKit.with_tenant('acme') do
        ConsoleKit.with_tenant('globex') do
          ConsoleKit.with_tenant('initech') { seen[:third] = observable_state }
          seen[:back_to_second] = observable_state
        end
        seen[:back_to_first] = observable_state
      end
      seen.merge(back_to_start: observable_state)
    end
  end

  describe 'a scope opened on top of an existing tenant' do
    before { ConsoleKit.switch_tenant('acme') }

    it 'restores the tenant that was already in effect' do
      ConsoleKit.with_tenant('globex') { :noop }
      expect(observable_state).to eq(expected_state('acme'))
    end

    it 'still verifies against the restored tenant' do
      ConsoleKit.with_tenant('globex') { :noop }
      expect(ConsoleKit.verify_tenant!.tenant_key).to eq('acme')
    end
  end

  describe 'the value of the block' do
    it 'passes a plain return value through' do
      expect(ConsoleKit.with_tenant('acme') { 42 }).to eq(42)
    end

    it 'passes the value of a nested scope through' do
      expect(ConsoleKit.with_tenant('acme') { ConsoleKit.with_tenant('globex') { :inner } })
        .to eq(:inner)
    end
  end

  describe 'an exception raised inside the block' do
    it 'propagates the original exception' do
      expect { raising_scope }.to raise_error(RuntimeError, 'boom inside the scope')
    end

    it 'still restores the original state' do
      swallow_raising_scope
      expect(observable_state).to eq(expected_state(nil))
    end

    it 'still restores the enclosing tenant when the inner block raises' do
      expect(raising_inner_scope).to eq(expected_state('acme'))
    end

    def raising_scope
      ConsoleKit.with_tenant('acme') { raise 'boom inside the scope' }
    end

    def swallow_raising_scope
      raising_scope
    rescue RuntimeError
      nil
    end

    def raising_inner_scope
      ConsoleKit.with_tenant('acme') do
        begin
          ConsoleKit.with_tenant('globex') { raise 'boom inside the inner scope' }
        rescue RuntimeError
          nil
        end
        observable_state
      end
    end
  end

  describe 'an inner switch that never commits' do
    it 'raises out of the inner scope' do
      expect { failing_inner_scope { ConsoleKit.with_tenant('nonexistent') { :never } } }
        .to raise_error(ConsoleKit::TenantNotFoundError)
    end

    it 'leaves the outer scope completely on its own tenant' do
      expect(state_after_failed_inner_switch).to eq(expected_state('acme'))
    end

    it 'leaves the outer scope on its own tenant after a mid-transaction failure' do
      expect(state_after_unreachable_redis).to eq(expected_state('acme'))
    end

    it 'still restores the original state once the outer scope closes' do
      state_after_failed_inner_switch
      expect(observable_state).to eq(expected_state(nil))
    end

    def failing_inner_scope(&attempt)
      ConsoleKit.with_tenant('acme', &attempt)
    end

    def state_after_failed_inner_switch
      ConsoleKit.with_tenant('acme') do
        failed_switch('nonexistent')
        observable_state
      end
    end

    def state_after_unreachable_redis
      ConsoleKit.with_tenant('acme') do
        Redis.current.reachable = false
        failed_switch('globex')
        Redis.current.reachable = true
        observable_state
      end
    end
  end

  # The scope closes from an `ensure`, so a rollback failure raised there would
  # discard whatever the block was already raising - the exact failure the
  # operator called about.
  describe 'a rollback that fails while the block is already raising' do
    let(:handlers) { ConsoleKit::Connections::ConnectionManager.available_handlers(context_class) }
    let(:sql) { handlers.find { |handler| handler.backend_key == :sql } }

    before do
      allow(ConsoleKit::Connections::ConnectionManager).to receive(:available_handlers).and_return(handlers)
      allow(sql).to receive(:restore).and_raise(IOError, 'shard registry offline')
      allow(ConsoleKit::Output).to receive(:print_error)
    end

    it 'propagates the exception the block raised' do
      expect { io_scope }.to raise_error(IOError, 'the REAL failure the operator needs')
    end

    it 'still reports the rollback failure through Output' do
      swallow_io_scope
      expect(ConsoleKit::Output).to have_received(:print_error).with(a_string_including('Rollback failed for'))
    end

    it 'says the rollback failure did not replace the root cause' do
      swallow_io_scope
      expect(ConsoleKit::Output).to have_received(:print_error).with(a_string_including('did not replace'))
    end

    it 'still raises the rollback failure when the block itself succeeded' do
      expect { ConsoleKit.with_tenant('acme') { :ok } }.to raise_error(ConsoleKit::RollbackError)
    end

    def io_scope
      ConsoleKit.with_tenant('acme') { raise IOError, 'the REAL failure the operator needs' }
    end

    def swallow_io_scope
      io_scope
    rescue IOError
      nil
    end
  end

  describe 'nesting inside a thread' do
    let(:trace) { trace_nested_scopes_on_a_thread }

    it 'reaches the inner tenant on that thread' do
      expect(trace[:inner][:tenant]).to eq('globex')
    end

    it 'returns to the outer tenant on that thread' do
      expect(trace[:after_inner][:tenant]).to eq('acme')
    end

    it 'returns that thread to the original state' do
      expect(trace[:after_outer][:tenant]).to be_nil
    end

    it 'leaves the process-wide backends back where they started' do
      trace
      expect(identities).to eq(expected_identities(nil))
    end

    it 'never gives the main thread a tenant of its own' do
      trace
      expect(ConsoleKit.current_tenant).to be_nil
    end

    def trace_nested_scopes_on_a_thread
      tenant_thread do
        seen = {}
        ConsoleKit.with_tenant('acme') do
          ConsoleKit.with_tenant('globex') { seen[:inner] = observable_state }
          seen[:after_inner] = observable_state
        end
        seen.merge(after_outer: observable_state)
      end.value
    end
  end
end
