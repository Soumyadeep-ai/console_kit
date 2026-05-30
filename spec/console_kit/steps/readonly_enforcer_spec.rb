# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Steps::ReadonlyEnforcer do
  subject(:step) { described_class.new(ctx) }

  let(:config) { ConsoleKit.configuration }
  let(:ctx)    { ConsoleKit::PipelineContext.new(config: config) }

  before do
    ConsoleKit.configure do |c|
      c.tenants       = { tenant_a: { constants: { shard: 's1', partner_code: 'pa' } } }
      c.context_class = 'Object'
    end
    ctx.resolved_tenant = :tenant_a
    allow(ConsoleKit::Output).to receive(:print_banner)
  end

  after { ConsoleKit::ReadonlyMode.deactivate! }

  context 'when readonly_mode false and readonly_environments empty' do
    it 'returns success' do
      expect(step.call.success?).to be true
    end

    it 'does not activate readonly mode' do
      step.call
      expect(ConsoleKit::ReadonlyMode.active?).to be false
    end
  end

  context 'when readonly_mode is true' do
    let(:ar_base) do
      Class.new do
        def self.save
          :saved
        end
      end
    end

    before do
      config.readonly_mode = true
      stub_const('ActiveRecord::Base', ar_base)
      ConsoleKit::ReadonlyMode.instance_variable_set(:@installed, false)
    end

    after { ConsoleKit::ReadonlyMode.instance_variable_set(:@installed, false) }

    it 'returns success' do
      expect(step.call.success?).to be true
    end

    it 'activates readonly mode' do
      step.call
      expect(ConsoleKit::ReadonlyMode.active?).to be true
    end

    it 'prints readonly banner' do
      step.call
      expect(ConsoleKit::Output).to have_received(:print_banner)
    end

    it 'blocks AR instance write methods after call' do
      step.call
      record = ar_base.new
      expect { record.save }.to raise_error(ConsoleKit::ReadonlyViolation)
    end
  end

  context 'when current env is in readonly_environments' do
    before do
      config.readonly_environments = %w[production]
      stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'production'))
      hide_const('Rails')
      stub_const('ActiveRecord::Base', Class.new)
    end

    it 'activates readonly mode' do
      step.call
      expect(ConsoleKit::ReadonlyMode.active?).to be true
    end
  end

  context 'when tenants is :dynamic with explicit readonly_mode = true' do
    before do
      ConsoleKit.configure do |c|
        c.tenants         = :dynamic
        c.tenant_resolver = ->(key) { { partner_code: key.to_s } }
        c.context_class   = 'Object'
        c.readonly_mode   = true
      end
      stub_const('ActiveRecord::Base', Class.new)
      ConsoleKit::ReadonlyMode.instance_variable_set(:@installed, false)
    end

    after { ConsoleKit::ReadonlyMode.instance_variable_set(:@installed, false) }

    it 'activates readonly mode' do
      step.call
      expect(ConsoleKit::ReadonlyMode.active?).to be true
    end
  end

  context 'when tenants is :dynamic with env-based enforcement only' do
    before do
      ConsoleKit.configure do |c|
        c.tenants                = :dynamic
        c.tenant_resolver        = ->(key) { { partner_code: key.to_s } }
        c.context_class          = 'Object'
        c.readonly_environments  = ['production']
      end
      hide_const('Rails')
      stub_const('ENV', ENV.to_h.merge('RAILS_ENV' => 'production'))
      stub_const('ActiveRecord::Base', Class.new)
    end

    it 'does not activate readonly mode via env enforcement in dynamic mode' do
      step.call
      expect(ConsoleKit::ReadonlyMode.active?).to be false
    end
  end

  context 'when ActiveRecord::Base is not defined' do
    before do
      hide_const('ActiveRecord::Base')
      config.readonly_mode = true
    end

    it 'does not activate readonly mode' do
      step.call
      expect(ConsoleKit::ReadonlyMode.active?).to be false
    end
  end

  context 'when Rails.env is production' do
    before do
      rails_double = double('Rails') # rubocop:disable RSpec/VerifiedDoubles
      allow(rails_double).to receive(:respond_to?).with(:env).and_return(true)
      allow(rails_double).to receive(:env).and_return(double('env', to_s: 'production')) # rubocop:disable RSpec/VerifiedDoubles
      stub_const('Rails', rails_double)
      config.readonly_environments = ['production']
      stub_const('ActiveRecord::Base', Class.new)
    end

    it 'activates readonly mode' do
      step.call
      expect(ConsoleKit::ReadonlyMode.active?).to be true
    end
  end

  context 'when RACK_ENV is used as fallback' do
    before do
      hide_const('Rails')
      stub_const('ENV', ENV.to_h.except('RAILS_ENV').merge('RACK_ENV' => 'staging'))
      config.readonly_environments = ['staging']
      stub_const('ActiveRecord::Base', Class.new)
    end

    it 'activates readonly mode based on RACK_ENV' do
      step.call
      expect(ConsoleKit::ReadonlyMode.active?).to be true
    end
  end

  context 'when neither RAILS_ENV nor RACK_ENV is set' do
    before do
      hide_const('Rails')
      stub_const('ENV', ENV.to_h.except('RAILS_ENV', 'RACK_ENV'))
      config.readonly_environments = ['development']
      stub_const('ActiveRecord::Base', Class.new)
    end

    it 'falls back to development' do
      step.call
      expect(ConsoleKit::ReadonlyMode.active?).to be true
    end
  end
end
