# frozen_string_literal: true

require 'spec_helper'
require 'open3'

module StandaloneLoad
end

RSpec.describe StandaloneLoad do
  let(:lib_path) { File.expand_path('../../lib', __dir__) }

  def standalone(expression)
    Open3.capture3('ruby', "-I#{lib_path}", '-e', "require 'console_kit'; print(#{expression})").first
  end

  it 'loads without error' do
    expect(standalone('ConsoleKit::VERSION.class')).to eq('String')
  end

  it 'has Object#try, which the gem calls on every switch' do
    expect(standalone('Object.new.respond_to?(:try)')).to eq('true')
  end

  it 'has Time.current, which Output calls on every printed line' do
    expect(standalone('Time.respond_to?(:current)')).to eq('true')
  end

  it 'labels the IRB prompt when applied before Rails has loaded IRB' do
    expect(standalone('(ConsoleKit::Prompt.apply; IRB::Context.include?(ConsoleKit::Prompt::IrbLabel))')).to eq('true')
  end
end
