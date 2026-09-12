# frozen_string_literal: true

RSpec.describe ConsoleKit::Connections::RedisClientAdapter do
  subject(:adapter) { described_class.new }

  # A client that is reachable on the thread asking, but not on the thread the
  # probe runs on. Nothing has been learned about isolation here - the probe
  # simply could not observe anything.
  describe 'when the probe thread cannot reach the client' do
    let(:client) { RedisFakes::DbReader.new }

    before do
      owner = Thread.current
      reachable = client
      fake = Module.new
      fake.define_singleton_method(:current) { Thread.current.equal?(owner) ? reachable : nil }
      stub_const('Redis', fake)
    end

    it 'reports :unknown rather than claiming isolation it did not observe' do
      expect(adapter.isolation_model).to eq(:unknown)
    end

    it 'never reports :scoped, which is what the handler reads as thread isolated' do
      expect(adapter.isolation_model).not_to eq(:scoped)
    end
  end
end
