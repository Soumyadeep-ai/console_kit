# spec/generators/console_kit/doctor_generator_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'generators/console_kit/doctor_generator'

RSpec.describe ConsoleKit::Generators::DoctorGenerator do
  let(:generator) { described_class.new }

  before do
    # Stub exit to prevent actual process termination
    allow(generator).to receive(:exit)
    allow($stdout).to receive(:puts)
  end

  describe '#run_checks' do
    context 'when all checks pass' do
      before do
        ConsoleKit.configure do |c|
          c.tenants = { main: { constants: { shard: 'a', partner_code: 'b' } } }
          c.context_class = 'Object'
        end
      end

      it 'does not call exit' do
        generator.run_checks
        expect(generator).not_to have_received(:exit)
      end
    end

    context 'when checks produce errors' do
      it 'calls exit(1)' do
        # Default config has no tenants, so TenantsConfigured will error
        generator.run_checks
        expect(generator).to have_received(:exit).with(1)
      end
    end
  end

  describe '#require_doctor_files' do
    it 'requires all doctor check files without raising' do
      expect { generator.send(:require_doctor_files) }.not_to raise_error
    end
  end
end
