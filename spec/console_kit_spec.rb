# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit do
  it 'has a version number' do
    expect(ConsoleKit::VERSION).not_to be nil
  end

  it 'responds to setup' do
    expect(ConsoleKit).to respond_to(:setup)
  end
end
