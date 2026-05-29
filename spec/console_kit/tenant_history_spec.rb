# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe ConsoleKit::TenantHistory do
  subject(:history) { described_class.new(tmpfile, 3) }

  let(:tmpfile) { File.join(Dir.tmpdir, "ck_history_#{Process.pid}") }

  after { FileUtils.rm_f(tmpfile) }

  describe '#recent' do
    it 'returns empty array when file does not exist' do
      expect(history.recent).to eq([])
    end

    it 'returns recorded tenants most-recent first' do
      history.record(:tenant_a)
      history.record(:tenant_b)
      expect(history.recent.first).to eq('tenant_b')
    end

    it 'respects the limit' do
      history.record(:a)
      history.record(:b)
      history.record(:c)
      history.record(:d)
      expect(history.recent.length).to eq(3)
    end
  end

  describe '#record' do
    it 'deduplicates entries' do
      history.record(:tenant_a)
      history.record(:tenant_a)
      expect(history.recent.length).to eq(1)
    end

    it 'does not raise when path is unwritable' do
      bad_history = described_class.new('/nonexistent/path/history', 5)
      expect { bad_history.record(:tenant_a) }.not_to raise_error
    end

    it 'sanitizes newlines in tenant name to prevent history injection' do
      history.record("acme\nevil")
      expect(history.recent).to eq(['acme_evil'])
    end

    it 'does not create extra entries when tenant contains newline' do
      history.record("acme\nevil")
      expect(history.recent.length).to eq(1)
    end

    it 'sanitizes carriage return in tenant name' do
      history.record("acme\revil")
      expect(history.recent).to eq(['acme_evil'])
    end
  end
end
