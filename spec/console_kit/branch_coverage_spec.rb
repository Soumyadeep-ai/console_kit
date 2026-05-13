# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ConsoleKit branch coverage' do
  describe 'reset_configuration!' do
    it 'resets configuration success if TenantConfigurator is defined' do
      stub_const('ConsoleKit::TenantConfigurator', Module.new)
      ConsoleKit::TenantConfigurator.define_singleton_method(:configuration_success=) { |v| @success = v }
      ConsoleKit::TenantConfigurator.define_singleton_method(:configuration_success) { @success }

      ConsoleKit.reset_configuration!
      expect(ConsoleKit::TenantConfigurator.configuration_success).to be false
    end
  end
end
