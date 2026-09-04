# frozen_string_literal: true

require 'spec_helper'

# Invariant 1, driven over whole sequences rather than single switches: at every
# observable point ConsoleKit is either still on the previous tenant or
# completely on the new one, never a mixture.
#
# Two rules are checked after EVERY step:
#
#   verify_consistency!  after a SUCCESSFUL switch - the tenant key, every
#                        context value and all four backend identities agree
#                        with that tenant's configured constants
#   verify_restored!     after a FAILED switch - everything matches the
#                        pre-switch snapshot exactly
#
# Both return a description of the disagreement, or nil, so a sequence collapses
# to one expectation whose failure output names the step that broke.

# Inputs for the generated sequences. The seed is fixed and travels with the
# result, so a failure names the seed that reproduces it. `nonexistent` is not a
# configured tenant, so it always lands as a failed step: the generated run
# exercises rollback as well as commit.
module SwitchSequence
  SEED = 20_250_904
  LENGTH = 24
  KEYS = %w[acme globex initech nonexistent].freeze
end

RSpec.describe SwitchSequence do
  include_context 'with a four-backend tenant setup'

  describe 'the sequences the release brief calls out' do
    it 'holds every invariant across A -> B -> C -> A' do
      expect(run(%w[acme globex initech acme])).to be_empty
    end

    it 'holds every invariant across A -> B -> failure -> C' do
      expect(run(%w[acme globex nonexistent initech])).to be_empty
    end

    it 'holds every invariant across B -> B' do
      expect(run(%w[globex globex])).to be_empty
    end

    it 'holds every invariant across C -> A -> failure -> B' do
      expect(run(%w[initech acme nonexistent globex])).to be_empty
    end

    it 'holds every invariant across A -> A' do
      expect(run(%w[acme acme])).to be_empty
    end

    it 'holds every invariant across a clear in the middle of a sequence' do
      expect(run(['acme', 'globex', nil, 'initech'])).to be_empty
    end
  end

  describe 'a generated sequence' do
    it 'holds every invariant, reproducibly from a fixed seed' do
      expect(seeded_run).to eq(seed: SwitchSequence::SEED, mismatches: [])
    end
  end

  describe 'switching to the tenant already in effect' do
    before { ConsoleKit.switch_tenant('acme') }

    it 'stays fully consistent' do
      ConsoleKit.switch_tenant('acme')
      expect(verify_consistency!('acme')).to be_nil
    end

    it 'never churns a connection pool' do
      ConsoleKit.switch_tenant('acme')
      expect(base_class.connection_handler.disconnects).to eq(0)
    end

    it 'still verifies against its own tenant' do
      ConsoleKit.switch_tenant('acme')
      expect(ConsoleKit.verify_tenant!.tenant_key).to eq('acme')
    end
  end

  describe 'a sequence whose middle step fails inside the transaction' do
    # acme -> globex, where Redis refuses the SELECT after SQL and Mongo have
    # already moved -> initech, once Redis is reachable again.
    let(:report) { run_with_unreachable_redis }

    it 'restores every observable after the failed middle step' do
      expect(report[:after_failure]).to be_nil
    end

    it 'reports the failure rather than committing it' do
      expect(report[:error]).to be_a(ConsoleKit::TenantSwitchError)
    end

    it 'switches cleanly to the next tenant afterwards' do
      expect(report[:after_recovery]).to be_nil
    end

    def run_with_unreachable_redis
      ConsoleKit.switch_tenant('acme')
      snapshot = observable_state
      Redis.current.reachable = false
      error = failed_switch('globex')
      after_failure = verify_restored!('globex', snapshot)
      Redis.current.reachable = true
      ConsoleKit.switch_tenant('initech')
      { error: error, after_failure: after_failure, after_recovery: verify_consistency!('initech') }
    end
  end

  # --- the two rules ---------------------------------------------------

  # After a SUCCESSFUL switch: tenant key, context values and all four backend
  # identities agree with the tenant's configured constants.
  def verify_consistency!(key) = mismatch(key, expected_state(key))

  # After a FAILED switch: everything matches the pre-switch snapshot exactly.
  def verify_restored!(key, snapshot) = mismatch(key, snapshot)

  def mismatch(step, expected)
    observed = observable_state
    { step: step, expected: expected, observed: observed } unless observed == expected
  end

  # --- driving ---------------------------------------------------------

  # Drives a sequence, applying the right rule after every step. Returns one row
  # per step that disagreed, so an empty result means the whole run held.
  def run(steps)
    [mismatch(:initial, expected_state(nil)), *steps.map { |step| step_mismatch(step) }].compact
  end

  def step_mismatch(step)
    snapshot = observable_state
    failed_switch(step) ? verify_restored!(step, snapshot) : verify_consistency!(step)
  end

  def seeded_run = { seed: SwitchSequence::SEED, mismatches: run(generated_sequence) }

  def generated_sequence
    random = Random.new(SwitchSequence::SEED)
    Array.new(SwitchSequence::LENGTH) { SwitchSequence::KEYS[random.rand(SwitchSequence::KEYS.size)] }
  end
end
