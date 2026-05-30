# spec/console_kit/doctor/check_runner_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::CheckRunner do
  subject(:runner) { described_class.new(config) }

  let(:config) { ConsoleKit.configuration }

  describe '#run' do
    it 'returns an array of Results' do
      results = runner.run
      expect(results).to all(be_a(ConsoleKit::Doctor::Checks::Base::Result))
    end

    it 'runs all registered checks' do
      expect(runner.run.size).to eq(ConsoleKit::Doctor::CheckRegistry.all.size)
    end
  end
end
