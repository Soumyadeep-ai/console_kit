# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::Checks::PresetConfigValid do
  subject(:check) { described_class.new(config) }

  let(:config) { ConsoleKit.configuration }

  context 'when no presets configured' do
    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end

    it 'message includes not configured' do
      expect(check.call.message).to include('no presets')
    end
  end

  context 'when presets use valid attributes' do
    before do
      config.presets = {
        support: { readonly_mode: true },
        ops: { confirm_dangerous_context: false }
      }
    end

    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end

    it 'message includes preset count' do
      expect(check.call.message).to include('2')
    end
  end

  context 'when a preset contains an unknown attribute' do
    before do
      config.presets = { bad: { nonexistent_option: true } }
    end

    it 'returns warn status' do
      expect(check.call.status).to eq(:warn)
    end

    it 'message includes the invalid attribute name' do
      expect(check.call.message).to include('nonexistent_option')
    end
  end

  context 'when preset has mix of valid and invalid attributes' do
    before do
      config.presets = { mixed: { readonly_mode: true, fake_attr: 'bad' } }
    end

    it 'returns warn status' do
      expect(check.call.status).to eq(:warn)
    end

    it 'only reports invalid attribute' do
      expect(check.call.message).to include('fake_attr')
    end
  end
end
