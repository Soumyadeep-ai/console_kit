# frozen_string_literal: true

require 'spec_helper'
require 'generators/console_kit/install_generator'
require 'pathname'
require 'fileutils'

# Stub Rails.root because this is not a Rails app
module Rails
  def self.root
    Pathname.new(Dir.pwd)
  end
end

RSpec.describe ConsoleKit::Generators::InstallGenerator, type: :generator do
  include GeneratorSpec::TestCase

  destination File.expand_path('../../tmp/generator_test', __dir__)

  before(:all) { prepare_destination }
  after(:all) { FileUtils.rm_rf(destination_root) }

  let(:initializer_path) { 'config/initializers/console_kit.rb' }
  let(:full_path) { File.join(destination_root, initializer_path) }

  context 'when initializer does not exist' do
    it 'creates initializer and prints messages' do
      output = run_generator
      expect(File).to exist(full_path)

      content = File.read(full_path)
      expect(content).to include('ConsoleKit.configure')

      expect(output).to include('created')
      expect(output).to include('Setup complete')
    end

    it 'writes correct configuration content' do
      run_generator
      content = File.read(full_path)

      expect(content).to include('ConsoleKit.configure do |config|')
      expect(content).to include('config.tenants')
      expect(content).to include('config.context_class')
    end

    it 'creates config/initializers directory if missing' do
      FileUtils.rm_rf(File.join(destination_root, 'config'))
      run_generator

      expect(Dir.exist?(File.join(destination_root, 'config/initializers'))).to be true
    end
  end

  context 'when initializer already exists' do
    before do
      run_generator
    end

    it 'skips by default if file exists' do
      output = run_generator
      expect(output).to include('skipped').or include('identical')
    end

    it 'overwrites with --force' do
      output = run_generator %w[--force]
      expect(output).to include('created')
    end

    it 'overwrites existing initializer content with --force' do
      File.write(full_path, 'old content')

      run_generator %w[--force]

      content = File.read(full_path)
      expect(content).to include('ConsoleKit.configure')
      expect(content).not_to include('old content')
    end
  end

  context 'idempotency' do
    it 'is idempotent when run multiple times without --force' do
      run_generator
      output = run_generator

      expect(output).to include('skipped').or include('identical')
    end
  end

  context 'output messages' do
    it 'outputs helpful instructions after creation' do
      output = run_generator

      expect(output).to match(/Setup complete!/)
      expect(output).to match(%r{Modify `config/initializers/console_kit.rb`})
    end
  end

  context 'invalid options' do
    it 'does not raise error with unknown options' do
      expect { run_generator %w[--unknown-option] }.not_to raise_error
    end
  end
end
