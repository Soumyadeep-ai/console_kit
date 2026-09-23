# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Prompt do
  let(:tenant) { ['acme'] }

  before { allow(ConsoleKit::StateStore).to receive(:tenant_key) { tenant.first } }

  describe 'an IRB session' do
    let(:context_class) { Class.new { attr_accessor :prompt_i, :prompt_s, :prompt_c } }
    let(:context) do
      context_class.new.tap do |c|
        c.prompt_i = 'app(prod)> '
        c.prompt_s = 'app(prod)%l '
      end
    end

    before do
      stub_const('IRB::Context', context_class)
      described_class.apply
    end

    it 'prefixes the current tenant' do
      expect(context.prompt_i).to eq('[acme] app(prod)> ')
    end

    it 'follows a tenant switch without being applied again' do
      tenant[0] = 'globex'
      expect(context.prompt_i).to eq('[globex] app(prod)> ')
    end

    it 'shows no tenant once the tenant is cleared' do
      tenant[0] = nil
      expect(context.prompt_i).to eq('[no-tenant] app(prod)> ')
    end

    it 'keeps the continuation prompt in step' do
      expect(context.prompt_s).to eq('[acme] app(prod)%l ')
    end

    it 'leaves a prompt IRB did not set unset' do
      expect(context.prompt_c).to be_nil
    end

    it 'escapes % so IRB does not read a tenant name as a format directive' do
      tenant[0] = '50%off'
      expect(context.prompt_i).to eq('[50%%off] app(prod)> ')
    end

    it 'decorates once however often it is applied' do
      described_class.apply
      expect(context.prompt_i).to eq('[acme] app(prod)> ')
    end
  end

  describe 'a Pry session' do
    let(:config) { Struct.new(:prompt).new }

    before do
      cfg = config
      stub_const('IRB::Context', Class.new)
      stub_const('Pry', Module.new { define_singleton_method(:config) { cfg } })
      described_class.apply
    end

    def render = config.prompt.first.call('main', 0, nil)

    it 'prefixes the current tenant' do
      expect(render).to eq('[acme] (main):0> ')
    end

    it 'follows a tenant switch without being applied again' do
      tenant[0] = 'globex'
      expect(render).to eq('[globex] (main):0> ')
    end

    it 'shows no tenant once the tenant is cleared' do
      tenant[0] = nil
      expect(render).to eq('[no-tenant] (main):0> ')
    end
  end

  describe 'a console with neither IRB nor Pry' do
    before do
      hide_const('IRB')
      hide_const('Pry')
    end

    it 'does nothing' do
      expect { described_class.apply }.not_to raise_error
    end
  end
end
