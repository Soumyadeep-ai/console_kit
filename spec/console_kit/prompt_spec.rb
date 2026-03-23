# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Prompt do
  before do
    allow(ConsoleKit::Setup).to receive(:current_tenant).and_return('acme')
  end

  describe '.apply' do
    context 'when IRB is defined' do
      let(:irb_conf) { { PROMPT: {}, PROMPT_MODE: nil } }

      before do
        irb_module = Module.new do
          def self.conf; end
        end
        stub_const('IRB', irb_module)
        allow(IRB).to receive(:conf).and_return(irb_conf)
      end

      it 'sets the IRB prompt' do
        described_class.apply
        expect(irb_conf[:PROMPT][:CONSOLE_KIT]).to be_a(Hash)
      end

      it 'includes the tenant name in the prompt' do
        described_class.apply
        expect(irb_conf[:PROMPT][:CONSOLE_KIT][:PROMPT_I]).to include('[acme]')
      end

      it 'sets CONSOLE_KIT as the prompt mode' do
        described_class.apply
        expect(irb_conf[:PROMPT_MODE]).to eq(:CONSOLE_KIT)
      end
    end

    context 'when IRB is defined with nil PROMPT hash' do
      let(:irb_conf) { { PROMPT: nil, PROMPT_MODE: nil } }

      before do
        irb_module = Module.new do
          def self.conf; end
        end
        stub_const('IRB', irb_module)
        allow(IRB).to receive(:conf).and_return(irb_conf)
      end

      it 'initializes PROMPT hash and sets the prompt' do
        described_class.apply
        expect(irb_conf[:PROMPT][:CONSOLE_KIT]).to be_a(Hash)
      end
    end

    context 'when Pry is defined' do
      let(:pry_config) { Struct.new(:prompt).new }

      before do
        pry_prompt_class = Class.new do
          attr_reader :name, :description, :procs

          def initialize(name, description, procs)
            @name = name
            @description = description
            @procs = procs
          end
        end

        pry_class = Class.new do
          def self.config; end
        end

        stub_const('Pry', pry_class)
        stub_const('Pry::Prompt', pry_prompt_class)
        allow(Pry).to receive(:config).and_return(pry_config)
      end

      it 'sets the Pry prompt' do
        described_class.apply
        expect(pry_config.prompt).to be_a(Pry::Prompt)
      end

      it 'includes the tenant name in the prompt procs' do
        described_class.apply
        prompt_text = pry_config.prompt.procs[0].call('main', 0, nil)
        expect(prompt_text).to include('[acme]')
      end
    end

    context 'when Pry is defined but Pry::Prompt does not support .new' do
      let(:pry_config) { Struct.new(:prompt).new }

      before do
        pry_class = Class.new do
          def self.config; end
        end
        stub_const('Pry', pry_class)
        # Do NOT define Pry::Prompt — simulates old Pry
        allow(Pry).to receive(:config).and_return(pry_config)
      end

      it 'sets the Pry prompt as an array' do
        described_class.apply
        expect(pry_config.prompt).to be_an(Array).and have_attributes(length: 2)
      end

      it 'uses procs for the prompt entries' do
        described_class.apply
        expect(pry_config.prompt.first).to be_a(Proc)
      end

      it 'includes the tenant name in the fallback prompt' do
        described_class.apply
        prompt_text = pry_config.prompt.first.call('main', 0, nil)
        expect(prompt_text).to include('[acme]')
      end
    end

    context 'when neither IRB nor Pry is defined' do
      it 'does not raise an error' do
        expect { described_class.apply }.not_to raise_error
      end
    end
  end
end
