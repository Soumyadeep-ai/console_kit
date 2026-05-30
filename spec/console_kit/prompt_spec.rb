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

    context 'when Pry is defined (legacy proc API)' do
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

    context 'when Pry::Prompt API is available' do
      let(:pry_cfg) { double('pry_config') } # rubocop:disable RSpec/VerifiedDoubles
      let(:captured_procs) { [] }
      let(:prompt_instance) { double('prompt_instance') } # rubocop:disable RSpec/VerifiedDoubles
      let(:pry_prompt_class) { double('Pry::Prompt class') } # rubocop:disable RSpec/VerifiedDoubles

      before do
        hide_const('IRB') if defined?(IRB)
        allow(pry_prompt_class).to receive(:new) do |_name, _desc, procs|
          captured_procs.concat(procs)
          prompt_instance
        end
        allow(pry_cfg).to receive(:prompt=)
        pry_module = Module.new
        pry_module.const_set(:Prompt, pry_prompt_class)
        allow(pry_module).to receive(:config).and_return(pry_cfg)
        stub_const('Pry', pry_module)
      end

      it 'sets prompt= with a Pry::Prompt instance' do
        described_class.apply
        expect(pry_cfg).to have_received(:prompt=).with(prompt_instance)
      end

      it 'secondary prompt proc includes *' do
        described_class.apply
        expect(captured_procs.last&.call).to include('*')
      end
    end

    context 'when IRB is defined with an active CurrentContext' do
      let(:irb_context) { double('IRB::Context') } # rubocop:disable RSpec/VerifiedDoubles

      before do
        hide_const('Pry') if defined?(Pry)
        allow(irb_context).to receive(:prompt_i=)
        allow(irb_context).to receive(:prompt_n=)
        allow(irb_context).to receive(:prompt_s=)
        allow(irb_context).to receive(:prompt_c=)
        stub_const('IRB', double('IRB', conf: irb_conf, CurrentContext: irb_context)) # rubocop:disable RSpec/VerifiedDoubles
      end

      it 'updates prompt strings on the running context' do
        described_class.apply
        expect(irb_context).to have_received(:prompt_i=).with(a_string_including('['))
      end
    end

    context 'when IRB is defined, CurrentContext is nil, MAIN_CONTEXT present' do
      let(:irb_context) { double('IRB::Context') } # rubocop:disable RSpec/VerifiedDoubles

      before do
        hide_const('Pry') if defined?(Pry)
        irb_conf[:MAIN_CONTEXT] = irb_context
        allow(irb_context).to receive(:prompt_i=)
        allow(irb_context).to receive(:prompt_n=)
        allow(irb_context).to receive(:prompt_s=)
        allow(irb_context).to receive(:prompt_c=)
        stub_const('IRB', double('IRB', conf: irb_conf, CurrentContext: nil)) # rubocop:disable RSpec/VerifiedDoubles
      end

      it 'falls back to MAIN_CONTEXT for prompt refresh' do
        described_class.apply
        expect(irb_context).to have_received(:prompt_i=)
      end
    end

    context 'when IRB is defined but no active context anywhere' do
      before do
        hide_const('Pry') if defined?(Pry)
        stub_const('IRB', double('IRB', conf: irb_conf, CurrentContext: nil)) # rubocop:disable RSpec/VerifiedDoubles
      end

      it 'does not raise' do
        expect { described_class.apply }.not_to raise_error
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
