# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in console_kit.gemspec
gemspec

gem 'irb'
gem 'rake', '~> 13.3'

group :development, :test do
  gem 'reek', '~> 6.5'
  gem 'rspec', '~> 3.13'
  gem 'rubocop', '~> 1.79'
  gem 'rubocop-rake'
  gem 'rubocop-rspec'
end

group :test do
  gem 'aruba'
  gem 'generator_spec'
  gem 'rspec_junit_formatter'
end
