# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Prompt do
  describe '#tenant_label' do
    let(:context) { ConsoleKit::Context.new(tenant: :tenant_a) }

    before do
      allow(ConsoleKit::Context).to receive(:current).and_return(context)
    end

    it 'returns tenant with env label' do
      stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'test'))
      prompt = described_class.new
      expect(prompt.tenant_label).to match(/\[tenant_a\]\[.+\]/)
    end

    it 'returns no-tenant when tenant is nil' do
      context_without_tenant = ConsoleKit::Context.new(tenant: nil)
      allow(ConsoleKit::Context).to receive(:current).and_return(context_without_tenant)
      prompt = described_class.new
      expect(prompt.tenant_label).to eq('[no-tenant]')
    end

    it 'includes tenant and env in label format' do
      context_env = ConsoleKit::Context.new(tenant: :tenant_b)
      allow(ConsoleKit::Context).to receive(:current).and_return(context_env)
      stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'staging'))
      prompt = described_class.new
      expect(prompt.tenant_label).to match(/\[tenant_b\]\[.+\]/)
    end

    it 'strips ANSI escape sequences from tenant name' do
      context_ansi = ConsoleKit::Context.new(tenant: "\e[31mhacked\e[0m")
      allow(ConsoleKit::Context).to receive(:current).and_return(context_ansi)
      prompt = described_class.new
      expect(prompt.tenant_label).not_to include("\e")
    end

    it 'strips ANSI escape sequences from env' do # rubocop:disable RSpec/ExampleLength
      rails_mock = double('Rails') # rubocop:disable RSpec/VerifiedDoubles
      allow(rails_mock).to receive_messages(
        respond_to?: true, env: double('env', to_s: "\e[31mprod\e[0m") # rubocop:disable RSpec/VerifiedDoubles
      )
      stub_const('Rails', rails_mock)
      expect(described_class.new.tenant_label).not_to include("\e")
    end
  end

  describe '.apply' do
    let(:context) { ConsoleKit::Context.new(tenant: :tenant_a) }
    let(:irb_conf) { {} }
    let(:pry_config) { instance_double(Object, prompt: nil) }

    before do
      allow(ConsoleKit::Context).to receive(:current).and_return(context)
      stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'test'))
    end

    it 'returns early when neither IRB nor Pry are defined' do
      hide_const('IRB') if defined?(IRB)
      hide_const('Pry') if defined?(Pry)
      expect(described_class.apply).to be_nil
    end

    context 'when IRB is defined' do
      before do
        hide_const('Pry') if defined?(Pry)
        stub_const('IRB', double('IRB', conf: irb_conf)) # rubocop:disable RSpec/VerifiedDoubles
      end

      it 'does not raise' do
        expect { described_class.apply }.not_to raise_error
      end

      it 'sets PROMPT_MODE to CONSOLE_KIT' do
        described_class.apply
        expect(irb_conf[:PROMPT_MODE]).to eq(:CONSOLE_KIT)
      end
    end

    context 'when Pry is defined' do
      let(:captured_prompt) { [] }
      let(:pry_cfg) { double('pry_config') } # rubocop:disable RSpec/VerifiedDoubles

      before do
        hide_const('IRB') if defined?(IRB)
        allow(pry_cfg).to receive(:prompt=) { |p| captured_prompt << p }
        stub_const('Pry', double('Pry', config: pry_cfg)) # rubocop:disable RSpec/VerifiedDoubles
      end

      it 'configures Pry prompt' do
        described_class.apply
        expect(captured_prompt).not_to be_empty
      end

      it 'prompt proc includes >' do
        described_class.apply
        result = captured_prompt.first&.call(nil, nil, nil)
        expect(result).to include('>')
      end
    end

    context 'when both IRB and Pry are defined' do
      let(:pry_cfg) { double('pry_config') } # rubocop:disable RSpec/VerifiedDoubles

      before do
        stub_const('IRB', double('IRB', conf: irb_conf)) # rubocop:disable RSpec/VerifiedDoubles
        allow(pry_cfg).to receive(:prompt=)
        stub_const('Pry', double('Pry', config: pry_cfg)) # rubocop:disable RSpec/VerifiedDoubles
      end

      it 'sets IRB PROMPT_MODE' do
        described_class.apply
        expect(irb_conf[:PROMPT_MODE]).to eq(:CONSOLE_KIT)
      end

      it 'configures Pry prompt' do
        described_class.apply
        expect(pry_cfg).to have_received(:prompt=)
      end
    end
  end

  describe 'rails_or_env_var' do
    let(:context) { ConsoleKit::Context.new(tenant: :t) }

    before { allow(ConsoleKit::Context).to receive(:current).and_return(context) }

    it 'returns Rails.env when Rails responds to :env' do
      rails_mock = double('Rails', env: double('env', to_s: 'production')) # rubocop:disable RSpec/VerifiedDoubles
      stub_const('Rails', rails_mock)
      prompt = described_class.new
      result = prompt.send(:rails_or_env_var)
      expect(result).to eq('production')
    end

    it 'returns RAILS_ENV from ENV when Rails not defined' do
      hide_const('Rails') if defined?(Rails)
      stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'staging'))
      prompt = described_class.new
      expect(prompt.send(:rails_or_env_var)).to eq('staging')
    end

    it 'returns unknown when Rails absent and no RAILS_ENV' do
      hide_const('Rails') if defined?(Rails)
      stub_const('ENV', ENV.to_h.except('RAILS_ENV'))
      prompt = described_class.new
      expect(prompt.send(:rails_or_env_var)).to eq('unknown')
    end
  end
end
