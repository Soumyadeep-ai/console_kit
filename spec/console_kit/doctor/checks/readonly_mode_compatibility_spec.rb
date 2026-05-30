# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::Checks::ReadonlyModeCompatibility do
  subject(:check) { described_class.new(config) }

  let(:config) { ConsoleKit.configuration }

  context 'when readonly mode not configured' do
    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end

    it 'includes not configured in message' do
      expect(check.call.message).to include('not configured')
    end
  end

  context 'when readonly_mode true and AR available' do
    before do
      config.readonly_mode = true
      stub_const('ActiveRecord::Base', Class.new)
    end

    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end

    it 'includes ActiveRecord in message' do
      expect(check.call.message).to include('ActiveRecord')
    end
  end

  context 'when readonly_mode true and AR not available' do
    before do
      config.readonly_mode = true
      hide_const('ActiveRecord::Base')
    end

    it 'returns error status' do
      expect(check.call.status).to eq(:error)
    end

    it 'includes ActiveRecord in message' do
      expect(check.call.message).to include('ActiveRecord')
    end
  end

  context 'when readonly_environments set and AR not available' do
    before do
      config.readonly_environments = %w[production]
      hide_const('ActiveRecord::Base')
    end

    it 'returns error status' do
      expect(check.call.status).to eq(:error)
    end
  end

  context 'when readonly_environments set and AR available' do
    before do
      config.readonly_environments = %w[production]
      stub_const('ActiveRecord::Base', Class.new)
    end

    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end
  end
end
