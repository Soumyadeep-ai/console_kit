# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe ConsoleKit::AuditLogger do
  subject(:logger) { described_class.new(tmpfile) }

  let(:tmpfile) { File.join(Dir.tmpdir, "ck_audit_#{Process.pid}.log") }

  after { FileUtils.rm_f(tmpfile) }

  describe '#log' do
    it 'creates the log file' do
      logger.log(tenant: :tenant_a, action: :tenant_switch)
      expect(File.exist?(tmpfile)).to be true
    end

    it 'writes tenant name' do
      logger.log(tenant: :tenant_a, action: :tenant_switch)
      expect(File.read(tmpfile)).to include('tenant=tenant_a')
    end

    it 'writes action' do
      logger.log(tenant: :tenant_a, action: :tenant_switch)
      expect(File.read(tmpfile)).to include('action=tenant_switch')
    end

    it 'writes status' do
      logger.log(tenant: :tenant_a, action: :tenant_switch, status: :success)
      expect(File.read(tmpfile)).to include('status=success')
    end

    it 'writes user field' do
      logger.log(tenant: :tenant_a, action: :tenant_switch)
      expect(File.read(tmpfile)).to include('user=')
    end

    it 'writes env field' do
      logger.log(tenant: :tenant_a, action: :tenant_switch)
      expect(File.read(tmpfile)).to include('env=')
    end

    it 'appends on successive calls' do
      logger.log(tenant: :tenant_a, action: :tenant_switch)
      logger.log(tenant: :tenant_b, action: :tenant_switch)
      expect(File.readlines(tmpfile).length).to eq(2)
    end

    it 'includes ISO8601 timestamp' do
      logger.log(tenant: :tenant_a, action: :tenant_switch)
      expect(File.read(tmpfile)).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    context 'when tenant contains newline' do
      it 'strips newline from tenant field so only one line is written' do
        logger.log(tenant: "acme\ninjected_payload", action: :tenant_switch)
        expect(File.readlines(tmpfile).length).to eq(1)
      end

      it 'replaces newline with underscore in tenant field' do
        logger.log(tenant: "acme\ninjected_payload", action: :tenant_switch)
        expect(File.read(tmpfile)).to include('tenant=acme_injected_payload')
      end
    end

    context 'when user value contains newline' do
      it 'strips newline from user field so only one line is written' do
        logger.log(tenant: :acme, action: :tenant_switch, user: "bob\nevil_user")
        expect(File.readlines(tmpfile).length).to eq(1)
      end
    end

    context 'when tenant contains pipe character' do
      it 'replaces pipe with underscore' do
        logger.log(tenant: 'acme|injection', action: :tenant_switch)
        expect(File.read(tmpfile)).to include('tenant=acme_injection')
      end
    end

    context 'when path is not writable' do
      before { allow(ConsoleKit::Output).to receive(:print_warning) }

      it 'does not raise' do
        bad = described_class.new('/nonexistent/audit.log')
        expect { bad.log(tenant: :x, action: :tenant_switch) }.not_to raise_error
      end

      it 'prints warning containing AuditLogger' do
        bad = described_class.new('/nonexistent/audit.log')
        bad.log(tenant: :x, action: :tenant_switch)
        expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including('AuditLogger'))
      end
    end

    context 'when USER env var absent' do
      before { stub_const('ENV', ENV.to_h.except('USER')) }

      it 'writes user=unknown' do
        logger.log(tenant: :tenant_a, action: :tenant_switch)
        expect(File.read(tmpfile)).to include('user=unknown')
      end
    end

    context 'when Rails is defined' do
      before do
        rails_double = double('Rails', env: double('env', to_s: 'production')) # rubocop:disable RSpec/VerifiedDoubles
        stub_const('Rails', rails_double)
        allow(rails_double).to receive(:respond_to?).with(:env).and_return(true)
      end

      it 'uses Rails.env for env field' do
        logger.log(tenant: :acme, action: :tenant_switch)
        expect(File.read(tmpfile)).to include('env=production')
      end
    end

    context 'when RAILS_ENV is set' do
      before do
        hide_const('Rails')
        stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'staging'))
      end

      it 'uses RAILS_ENV for env field' do
        logger.log(tenant: :acme, action: :tenant_switch)
        expect(File.read(tmpfile)).to include('env=staging')
      end
    end

    context 'when RACK_ENV is used as fallback' do
      before do
        hide_const('Rails')
        stub_const('ENV', ENV.to_h.except('RAILS_ENV').merge('RACK_ENV' => 'test'))
      end

      it 'uses RACK_ENV for env field' do
        logger.log(tenant: :acme, action: :tenant_switch)
        expect(File.read(tmpfile)).to include('env=test')
      end
    end

    context 'when neither Rails nor env vars are set' do
      before do
        hide_const('Rails')
        stub_const('ENV', ENV.to_h.except('RAILS_ENV', 'RACK_ENV'))
      end

      it 'defaults env to development' do
        logger.log(tenant: :acme, action: :tenant_switch)
        expect(File.read(tmpfile)).to include('env=development')
      end
    end
  end
end
