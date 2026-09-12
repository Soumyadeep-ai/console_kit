# frozen_string_literal: true

require 'spec_helper'
require 'shellwords'

# The suite loads Rails (through generator_spec), which pulls in the whole of
# ActiveSupport and hides every core extension the gem uses but never requires.
# A host application that only has ActiveSupport gets exactly what `console_kit`
# requires for itself, so that is what these examples measure: a child process
# whose only require is the gem.
module StandaloneLoad
end

RSpec.describe StandaloneLoad do
  let(:lib_path) { File.expand_path('../../lib', __dir__) }

  def standalone(expression)
    script = "require 'console_kit'; print(#{expression})"
    `ruby -I#{lib_path.shellescape} -e #{script.shellescape} 2>&1`
  end

  it 'loads without error' do
    expect(standalone('ConsoleKit::VERSION.class')).to eq('String')
  end

  # Used 14 times across SqlStrategy, BaseConnectionHandler, TenantSwitch and Prompt.
  it 'has Object#try, which the gem calls on every switch' do
    expect(standalone('Object.new.respond_to?(:try)')).to eq('true')
  end

  # Output timestamps every line it prints.
  it 'has Time.current, which Output calls on every printed line' do
    expect(standalone('Time.respond_to?(:current)')).to eq('true')
  end
end
