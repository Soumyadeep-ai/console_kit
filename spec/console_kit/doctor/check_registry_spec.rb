# spec/console_kit/doctor/check_registry_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::CheckRegistry do
  describe '.all' do
    it 'returns an array of all registered check classes' do
      expect(described_class.all).to include(ConsoleKit::Doctor::Checks::TenantsConfigured)
    end

    it 'returns a dup so mutations do not affect the registry' do
      original_count = described_class.all.size
      described_class.all << Class.new
      expect(described_class.all.size).to eq(original_count)
    end
  end
end
