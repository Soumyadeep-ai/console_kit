# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'

RuboCop::RakeTask.new

task default: %i[spec rubocop]

desc 'Run ConsoleKit performance benchmarks against the stateful fakes (no real DB/Redis/Mongo/Elasticsearch)'
task :benchmark do
  files = Dir[File.expand_path('benchmark/[0-9][0-9]_*.rb', __dir__)]
  abort('No benchmark files found under benchmark/.') if files.empty?

  files.each do |file|
    heading = "benchmark/#{File.basename(file)}"
    puts "\n#{'=' * 88}\n#{heading}\n#{'=' * 88}"
    ruby '-Ilib', file
  end
end
