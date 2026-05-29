# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::ReadonlyMode do
  after { described_class.deactivate! }

  describe '.active? / .activate! / .deactivate!' do
    it 'is inactive by default' do
      expect(described_class.active?).to be false
    end

    it 'returns true after activate!' do
      described_class.activate!
      expect(described_class.active?).to be true
    end

    it 'returns false after deactivate!' do
      described_class.activate!
      described_class.deactivate!
      expect(described_class.active?).to be false
    end
  end

  describe '.install!' do
    context 'when ActiveRecord::Base is not defined' do
      before { hide_const('ActiveRecord::Base') }

      it 'does not raise' do
        expect { described_class.install! }.not_to raise_error
      end
    end

    context 'when ActiveRecord::Base is defined' do
      let(:ar_base) { Class.new }

      before do
        stub_const('ActiveRecord::Base', ar_base)
        described_class.instance_variable_set(:@installed, false)
      end

      after { described_class.instance_variable_set(:@installed, false) }

      it 'prepends InstanceMethods to ActiveRecord::Base' do
        described_class.install!
        expect(ar_base.ancestors).to include(ConsoleKit::ReadonlyMode::InstanceMethods)
      end

      it 'prepends ClassMethods to ActiveRecord::Base singleton class' do
        described_class.install!
        expect(ar_base.singleton_class.ancestors).to include(ConsoleKit::ReadonlyMode::ClassMethods)
      end

      it 'is idempotent (does not prepend twice)' do
        described_class.install!
        count_before = ar_base.ancestors.count(ConsoleKit::ReadonlyMode::InstanceMethods)
        described_class.install!
        expect(ar_base.ancestors.count(ConsoleKit::ReadonlyMode::InstanceMethods)).to eq(count_before)
      end
    end
  end

  describe 'InstanceMethods write blocking' do
    let(:ar_record) do
      obj = Object.new
      obj.extend(ConsoleKit::ReadonlyMode::InstanceMethods)
      obj
    end

    before { described_class.activate! }

    ConsoleKit::ReadonlyMode::INSTANCE_WRITE_METHODS.each do |method_name|
      it "raises ReadonlyViolation on ##{method_name}" do
        expect { ar_record.send(method_name) }.to raise_error(ConsoleKit::ReadonlyViolation)
      end
    end
  end

  describe 'ClassMethods write blocking' do
    let(:ar_class) do
      klass = Class.new
      klass.singleton_class.prepend(ConsoleKit::ReadonlyMode::ClassMethods)
      klass
    end

    before { described_class.activate! }

    ConsoleKit::ReadonlyMode::CLASS_WRITE_METHODS.each do |method_name|
      it "raises ReadonlyViolation on .#{method_name}" do
        expect { ar_class.send(method_name) }.to raise_error(ConsoleKit::ReadonlyViolation)
      end
    end
  end

  describe 'InstanceMethods passthrough when inactive' do
    let(:ar_class) do
      klass = Class.new { def save = :saved }
      klass.prepend(ConsoleKit::ReadonlyMode::InstanceMethods)
      klass
    end

    it 'calls through to super when readonly mode is off' do
      expect(ar_class.new.save).to eq(:saved)
    end
  end

  describe 'ClassMethods passthrough when inactive' do
    let(:ar_class) do
      klass = Class.new { def self.create = :created }
      klass.singleton_class.prepend(ConsoleKit::ReadonlyMode::ClassMethods)
      klass
    end

    it 'calls through to super when readonly mode is off' do
      expect(ar_class.create).to eq(:created)
    end
  end

  describe 'Rails 7.1+ prevent_writes integration' do
    context 'when AR connection supports prevent_writes' do
      let(:ar_connection) { double('Connection') } # rubocop:disable RSpec/VerifiedDoubles
      let(:ar_base) do
        klass = Class.new
        allow(klass).to receive(:connection).and_return(ar_connection)
        klass
      end

      before do
        stub_const('ActiveRecord::Base', ar_base)
        allow(ar_connection).to receive(:respond_to?).with(:prevent_writes=).and_return(true)
        allow(ar_connection).to receive(:prevent_writes=)
        described_class.instance_variable_set(:@installed, false)
      end

      after { described_class.instance_variable_set(:@installed, false) }

      it 'sets prevent_writes=true on activate!' do
        described_class.install!
        described_class.activate!
        expect(ar_connection).to have_received(:prevent_writes=).with(true)
      end

      it 'sets prevent_writes=false on deactivate!' do
        described_class.install!
        described_class.deactivate!
        expect(ar_connection).to have_received(:prevent_writes=).with(false)
      end
    end

    context 'when AR connection does not support prevent_writes' do
      let(:ar_base) do
        klass = Class.new
        allow(klass).to receive(:connection).and_return(Object.new)
        klass
      end

      before do
        stub_const('ActiveRecord::Base', ar_base)
        described_class.instance_variable_set(:@installed, false)
      end

      after { described_class.instance_variable_set(:@installed, false) }

      it 'does not raise' do
        described_class.install!
        expect { described_class.activate! }.not_to raise_error
      end
    end

    context 'when connection raises on access' do
      let(:ar_base) do
        klass = Class.new
        allow(klass).to receive(:connection).and_raise(StandardError, 'not connected')
        klass
      end

      before do
        stub_const('ActiveRecord::Base', ar_base)
        described_class.instance_variable_set(:@installed, false)
      end

      after { described_class.instance_variable_set(:@installed, false) }

      it 'does not raise' do
        described_class.install!
        expect { described_class.activate! }.not_to raise_error
      end
    end

    context 'when ActiveRecord is not defined' do
      before { hide_const('ActiveRecord::Base') }

      it 'does not raise on activate!' do
        expect { described_class.activate! }.not_to raise_error
      end

      it 'does not raise on deactivate!' do
        expect { described_class.deactivate! }.not_to raise_error
      end
    end
  end
end
