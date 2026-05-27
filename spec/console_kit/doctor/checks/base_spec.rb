# spec/console_kit/doctor/checks/base_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::Checks::Base do
  let(:config) { ConsoleKit.configuration }

  describe '#call' do
    it 'raises NotImplementedError' do
      # Instantiate Base directly (subclass registration happens in .inherited)
      instance = described_class.allocate
      instance.instance_variable_set(:@config, config)
      expect { instance.call }.to raise_error(NotImplementedError)
    end
  end
end
