# spec/console_kit/connections/connection_manager_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Connections::ConnectionManager do
  describe '.available_handlers' do
    it 'returns an empty array by default' do
      expect(described_class.available_handlers(Object.new)).to eq([])
    end
  end
end
