# frozen_string_literal: true

# The contract every ConsoleKit connection handler must satisfy, so that adding
# a fifth backend later is a matter of writing a handler and pointing these
# examples at it rather than rediscovering the rules by hand.
#
# The including group supplies one memoized helper, `contract`, answering the
# HandlerContract::Subject interface, plus two methods:
#
#   prepare_invalid_target      - arranges whatever makes a target unapplyable
#                                 and returns that target
#   hide_contract_dependency!   - removes the backend's client library
#
# Ready-made groups for the four shipped backends live in
# spec/support/shared_contexts/connection_handler_contracts.rb.
RSpec.shared_examples 'a connection handler' do
  describe 'availability' do
    it 'answers available? with a boolean' do
      expect(contract.handler.available?).to be(true).or be(false)
    end

    it 'is available while its client library is loaded' do
      expect(contract.handler.available?).to be(true)
    end
  end

  describe 'a missing client library' do
    before { hide_contract_dependency! }

    it 'reports the backend as unavailable' do
      expect(contract.handler.available?).to be(false)
    end

    it 'answers without raising' do
      expect { contract.handler.available? }.not_to raise_error
    end

    it 'reports an unavailable diagnostics row' do
      expect(contract.handler.diagnostics(level: :basic)[:status]).to eq(:unavailable)
    end
  end

  describe '#prepare' do
    it 'mutates nothing' do
      probe = contract.mutation_probe
      contract.handler.prepare(contract.target)
      expect(contract.mutation_probe).to eq(probe)
    end

    it 'leaves the live identity where it found it' do
      identity = contract.identity
      contract.handler.prepare(contract.target)
      expect(contract.identity).to eq(identity)
    end

    it 'accepts a valid target' do
      expect { contract.handler.prepare(contract.target) }.not_to raise_error
    end

    it 'rejects a target it cannot apply' do
      expect { contract.handler.prepare(prepare_invalid_target) }.to raise_error(ConsoleKit::Error)
    end

    it 'mutates nothing when it rejects a target' do
      probe = contract.mutation_probe
      reject_target
      expect(contract.mutation_probe).to eq(probe)
    end
  end

  describe '#snapshot' do
    it 'mutates nothing' do
      probe = contract.mutation_probe
      contract.handler.snapshot
      expect(contract.mutation_probe).to eq(probe)
    end

    it 'is repeatable' do
      first = contract.handler.snapshot
      expect(contract.handler.snapshot).to eq(first)
    end

    it 'is still repeatable once a tenant is applied' do
      contract.handler.connect!(contract.target)
      first = contract.handler.snapshot
      expect(contract.handler.snapshot).to eq(first)
    end
  end

  describe '#connect! and #verify!' do
    it 'lands on the requested target' do
      contract.handler.connect!(contract.target)
      expect(contract.identity).to eq(contract.target)
    end

    it 'verifies a connection it just made' do
      contract.handler.connect!(contract.target)
      expect { contract.handler.verify!(contract.target) }.not_to raise_error
    end

    it 'raises ConnectionVerificationError when the live identity is foreign' do
      contract.handler.connect!(contract.target)
      contract.corrupt!
      expect { contract.handler.verify!(contract.target) }
        .to raise_error(ConsoleKit::ConnectionVerificationError)
    end

    it 'reports the identity it expected' do
      contract.handler.connect!(contract.target)
      contract.corrupt!
      expect { contract.handler.verify!(contract.target) }
        .to raise_error(an_object_having_attributes(expected: contract.target))
    end

    it 'names the backend on the verification error' do
      contract.handler.connect!(contract.target)
      contract.corrupt!
      expect { contract.handler.verify!(contract.target) }
        .to raise_error(an_object_having_attributes(backend: contract.handler.display_name))
    end

    it 'leaves every unrelated backend untouched' do
      others = contract.unrelated_identities
      contract.handler.connect!(contract.target)
      expect(contract.unrelated_identities).to eq(others)
    end
  end

  describe '#restore' do
    it 'returns the backend to the exact identity it snapshotted' do
      contract.handler.connect!(contract.previous_target)
      state = contract.handler.snapshot
      contract.handler.connect!(contract.target)
      contract.handler.restore(state)
      expect(contract.identity).to eq(contract.previous_target)
    end

    it 'verifies against the restored identity' do
      state = round_trip_snapshot
      contract.handler.restore(state)
      expect { contract.handler.verify!(contract.previous_target) }.not_to raise_error
    end

    it 'restores to the default when there was no previous value' do
      state = contract.handler.snapshot
      contract.handler.connect!(contract.target)
      contract.handler.restore(state)
      expect(contract.identity).to eq(contract.default_identity)
    end

    it 'takes the same snapshot again after restoring to the default' do
      state = contract.handler.snapshot
      contract.handler.connect!(contract.target)
      contract.handler.restore(state)
      expect(contract.handler.snapshot).to eq(state)
    end

    it 'leaves every unrelated backend untouched' do
      state = round_trip_snapshot
      others = contract.unrelated_identities
      contract.handler.restore(state)
      expect(contract.unrelated_identities).to eq(others)
    end
  end

  describe '#diagnostics' do
    it 'performs no network call at the basic level' do
      calls = contract.network_calls
      contract.handler.diagnostics(level: :basic)
      expect(contract.network_calls).to eq(calls)
    end

    it 'returns exactly the documented row keys' do
      expect(contract.handler.diagnostics(level: :basic).keys)
        .to contain_exactly(:name, :status, :latency_ms, :details)
    end

    it 'names itself with its display name' do
      expect(contract.handler.diagnostics(level: :basic)[:name]).to eq(contract.handler.display_name)
    end

    it 'reports a symbol status' do
      expect(contract.handler.diagnostics(level: :basic)[:status]).to be_a(Symbol)
    end

    it 'reports no latency at the basic level' do
      expect(contract.handler.diagnostics(level: :basic)[:latency_ms]).to be_nil
    end

    it 'reports details as a hash' do
      expect(contract.handler.diagnostics(level: :basic)[:details]).to be_a(Hash)
    end
  end

  # Applies the target, then hands back a snapshot of the previous identity.
  def round_trip_snapshot
    contract.handler.connect!(contract.previous_target)
    state = contract.handler.snapshot
    contract.handler.connect!(contract.target)
    state
  end

  def reject_target
    contract.handler.prepare(prepare_invalid_target)
  rescue ConsoleKit::Error
    nil
  end
end
