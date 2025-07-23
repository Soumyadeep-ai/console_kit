# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit do
  it 'has a version number' do
    expect(ConsoleKit::VERSION).not_to be nil
  end

  it 'has a semantic version string' do
    expect(ConsoleKit::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it 'responds to setup' do
    expect(ConsoleKit).to respond_to(:setup)
  end

  it 'defines a custom base error class' do
    expect(ConsoleKit::Error).to be < StandardError
  end

  it 'exposes configuration DSL' do
    expect { |b| ConsoleKit.configure(&b) }.to yield_with_args(ConsoleKit)
  end
end
