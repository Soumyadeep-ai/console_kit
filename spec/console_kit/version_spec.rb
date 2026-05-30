# spec/console_kit/version_spec.rb
# frozen_string_literal: true

require 'spec_helper'

# Re-load version.rb after SimpleCov starts so the constant-definition lines
# get recorded in the coverage report. (The gemspec loads version.rb before
# SimpleCov initializes, leaving those lines uncovered otherwise.)
load File.expand_path('../../lib/console_kit/version.rb', __dir__)

RSpec.describe 'ConsoleKit::VERSION' do
  it 'is defined as a String' do
    expect(ConsoleKit::VERSION).to be_a(String)
  end

  it 'follows semantic versioning format' do
    expect(ConsoleKit::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
