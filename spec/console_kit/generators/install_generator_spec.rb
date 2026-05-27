# frozen_string_literal: true

require 'spec_helper'
require 'generators/console_kit/install_generator'
require 'pathname'
require 'fileutils'

GENERATOR_DESTINATION = File.expand_path('../../tmp/generator_test', __dir__)

# Stub Rails.root to point at the generator destination so File.exist? checks work
module Rails
  def self.root
    Pathname.new(GENERATOR_DESTINATION)
  end
end

RSpec.describe ConsoleKit::Generators::InstallGenerator, type: :generator do
  include GeneratorSpec::TestCase

  destination GENERATOR_DESTINATION

  before(:all) { prepare_destination } # rubocop:disable RSpec/BeforeAfterAll
  after(:all) { FileUtils.rm_rf(destination_root) } # rubocop:disable RSpec/BeforeAfterAll

  let(:initializer_path) { 'config/initializers/console_kit.rb' }
  let(:full_path) { File.join(destination_root, initializer_path) }

  context 'when initializer does not exist' do
    before { FileUtils.rm_f(full_path) }

    it 'creates the initializer file' do
      run_generator
      expect(File).to exist(full_path)
    end

    it 'writes ConsoleKit.configure to initializer' do
      run_generator
      expect(File.read(full_path)).to include('ConsoleKit.configure')
    end

    it 'includes created in generator output' do
      output = run_generator
      expect(output).to include('created')
    end

    it 'includes Setup complete in generator output' do
      output = run_generator
      expect(output).to include('Setup complete')
    end

    it 'writes configure block opener to initializer' do
      run_generator
      expect(File.read(full_path)).to include('ConsoleKit.configure do |config|')
    end

    it 'writes tenants config to initializer' do
      run_generator
      expect(File.read(full_path)).to include('config.tenants')
    end

    it 'writes context_class config to initializer' do
      run_generator
      expect(File.read(full_path)).to include('config.context_class')
    end

    it 'creates config/initializers directory if missing' do
      FileUtils.rm_rf(File.join(destination_root, 'config'))
      run_generator
      expect(Dir.exist?(File.join(destination_root, 'config/initializers'))).to be true
    end
  end

  context 'when initializer already exists' do
    before { run_generator }

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
      expect(File.read(full_path)).to include('ConsoleKit.configure')
    end

    it 'does not keep old content after --force' do
      File.write(full_path, 'old content')
      run_generator %w[--force]
      expect(File.read(full_path)).not_to include('old content')
    end
  end

  context 'when idempotent' do
    it 'is idempotent when run multiple times without --force' do
      run_generator
      output = run_generator
      expect(output).to include('skipped').or include('identical')
    end
  end

  context 'with output messages' do
    before { FileUtils.rm_f(full_path) }

    it 'outputs Setup complete after creation' do
      output = run_generator
      expect(output).to match(/Setup complete!/)
    end

    it 'outputs modify instructions after creation' do
      output = run_generator
      expect(output).to match(%r{Modify `config/initializers/console_kit.rb`})
    end
  end

  context 'with invalid options' do
    before { FileUtils.rm_f(full_path) }

    it 'does not raise error with unknown options' do
      expect { run_generator %w[--unknown-option] }.not_to raise_error
    end
  end
end
