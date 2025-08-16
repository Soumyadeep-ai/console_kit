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

  let(:initializer_path) { 'config/initializers/console_kit.rb' }
  let(:full_path) { File.join(destination_root, initializer_path) }

  before { prepare_destination }
  after { FileUtils.rm_rf(destination_root) }

  context 'when initializer does not exist' do
    it 'creates the initializer file' do
      run_generator
      expect(File).to exist(full_path)
    end

    it 'contains ConsoleKit configuration' do
      run_generator
      content = File.read(full_path)
      expect(content).to include('ConsoleKit.configure')
    end

    it 'prints created message' do
      output = run_generator
      expect(output).to include('created')
    end

    it 'prints setup complete message' do
      output = run_generator
      expect(output).to include('Setup complete')
    end

    it 'includes ConsoleKit.configure block' do
      run_generator
      content = File.read(full_path)
      expect(content).to include('ConsoleKit.configure do |config|')
    end

    it 'includes config.tenants key' do
      run_generator
      content = File.read(full_path)
      expect(content).to include('config.tenants')
    end

    it 'includes config.context_class key' do
      run_generator
      content = File.read(full_path)
      expect(content).to include('config.context_class')
    end

    it 'creates config/initializers directory if missing' do
      FileUtils.rm_rf(File.join(destination_root, 'config'))
      run_generator
      expect(Dir.exist?(File.join(destination_root, 'config/initializers'))).to be true
    end
  end

  context 'when initializer already exists' do
    before { run_generator }

    it 'skips creation if file exists by default' do
      output = run_generator
      expect(output).to include('skipped').or include('identical')
    end

    it 'overwrites the file with --force option' do
      output = run_generator %w[--force]
      expect(output).to include('created')
    end

    it 'includes new content with --force' do
      File.write(full_path, 'old content')
      run_generator %w[--force]
      content = File.read(full_path)
      expect(content).to include('ConsoleKit.configure')
    end

    it 'removes old content with --force' do
      File.write(full_path, 'old content')
      run_generator %w[--force]
      content = File.read(full_path)
      expect(content).not_to include('old content')
    end
  end

  context 'when run multiple times without --force' do
    it 'is idempotent and skips duplicate creation' do
      run_generator
      output = run_generator
      expect(output).to include('skipped').or include('identical')
    end
  end

  context 'when generating output messages' do
    it 'outputs setup complete instructions' do
      output = run_generator
      expect(output).to match(/Setup complete!/)
    end

    it 'advises modifying the initializer file' do
      output = run_generator
      expect(output).to match(%r{Modify `config/initializers/console_kit.rb`})
    end
  end

  context 'when unknown options are passed' do
    it 'does not raise an error' do
      expect { run_generator %w[--unknown-option] }.not_to raise_error
    end
  end
end
