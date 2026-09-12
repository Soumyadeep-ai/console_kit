# frozen_string_literal: true

require 'spec_helper'

# `Thread.current[]` is fiber-local, but the SQL `connected_to` frame ConsoleKit
# pairs its bookkeeping with is thread-local - that is where Rails keeps
# `connected_to_stack`. Both halves of the one per-thread invariant therefore
# have to live in the same scope: a second fiber shares the connections of the
# thread it runs on, so it has to share the TenantState describing them.
module FiberScope
end

RSpec.describe FiberScope do
  include_context 'with a four-backend tenant setup'

  def in_fiber(&block) = Fiber.new(&block).resume

  describe 'a fiber on a thread that has switched' do
    before { ConsoleKit.switch_tenant('acme') }

    it 'reports the tenant its thread is actually connected to' do
      expect(in_fiber { ConsoleKit.current_tenant }).to eq('acme')
    end

    it 'reports that tenant as configured' do
      expect(in_fiber { ConsoleKit::StateStore.configured? }).to be(true)
    end

    it 'sees the same TenantState object the thread committed' do
      expect(in_fiber { ConsoleKit::StateStore.current }).to equal(ConsoleKit::StateStore.current)
    end
  end

  describe 'an Enumerator, which Ruby drives on a fiber of its own' do
    before { ConsoleKit.switch_tenant('acme') }

    it 'sees the tenant of the thread consuming it' do
      expect(Enumerator.new { |yielder| yielder << ConsoleKit.current_tenant }.next).to eq('acme')
    end
  end

  describe 'a switch performed inside a fiber' do
    before do
      in_fiber do
        ConsoleKit::Output.silent = true
        ConsoleKit.switch_tenant('acme')
      end
    end

    it 'is visible to the thread whose connections it moved' do
      expect(ConsoleKit.current_tenant).to eq('acme')
    end

    it 'agrees with the SQL frame, which Rails keeps per thread' do
      expect(identities[:sql]).to eq('shard_acme')
    end

    # ConsoleKit invents no isolation: Mongoid keeps its overrides in
    # `Thread.current[]`, so a switch inside a fiber moves only that fiber's Mongo.
    it 'leaves a backend whose own library is fiber-local behind in the fiber' do
      expect(Mongoid::Threaded.database_override).to be_nil
    end
  end
end
