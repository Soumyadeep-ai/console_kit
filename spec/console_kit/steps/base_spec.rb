# spec/console_kit/steps/base_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Steps::Base do
  subject(:step) { described_class.new(ctx) }

  let(:config) { ConsoleKit.configuration }
  let(:ctx)    { ConsoleKit::PipelineContext.new(config: config) }

  it 'raises NotImplementedError when call is not implemented' do
    expect { step.call }.to raise_error(NotImplementedError, /Base#call not implemented/)
  end

  describe '#current_env' do
    let(:concrete_step) do
      Class.new(described_class) do
        def call = success
        def env = current_env
      end.new(ctx)
    end

    it 'returns development when no env vars set' do
      hide_const('Rails')
      stub_const('ENV', ENV.to_h.except('RAILS_ENV', 'RACK_ENV'))
      expect(concrete_step.env).to eq('development')
    end

    it 'returns RAILS_ENV when set' do
      hide_const('Rails')
      stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'staging'))
      expect(concrete_step.env).to eq('staging')
    end

    it 'falls back to RACK_ENV when RAILS_ENV absent' do
      hide_const('Rails')
      stub_const('ENV', ENV.to_h.except('RAILS_ENV').merge('RACK_ENV' => 'test'))
      expect(concrete_step.env).to eq('test')
    end

    it 'uses Rails.env when Rails responds to :env' do
      rails_double = double('Rails') # rubocop:disable RSpec/VerifiedDoubles
      allow(rails_double).to receive(:respond_to?).with(:env).and_return(true)
      allow(rails_double).to receive(:env).and_return(double('env', to_s: 'production')) # rubocop:disable RSpec/VerifiedDoubles
      stub_const('Rails', rails_double)
      expect(concrete_step.env).to eq('production')
    end

    it 'ignores Rails constant when it does not respond to :env' do
      rails_double = double('Rails') # rubocop:disable RSpec/VerifiedDoubles
      allow(rails_double).to receive(:respond_to?).with(:env).and_return(false)
      stub_const('Rails', rails_double)
      stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'qa'))
      expect(concrete_step.env).to eq('qa')
    end
  end

  describe ConsoleKit::Steps::Base::Result do
    it 'reports success? true when success is true' do
      result = described_class.new(success: true)
      expect(result.success?).to be true
    end

    it 'reports failure? true when success is false' do
      result = described_class.new(success: false)
      expect(result.failure?).to be true
    end
  end
end
