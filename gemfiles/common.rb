# frozen_string_literal: true

# Shared by every gemfiles/*.gemfile; only the Rails pins differ, and those stay
# in the individual files.

gemspec path: '..'

gem 'irb'
gem 'rake', '~> 13.3'

group :development, :test do
  gem 'rspec', '~> 3.13'
  gem 'rubocop', '~> 1.85'
  gem 'rubocop-rake'
  gem 'rubocop-rspec'
end

group :test do
  gem 'generator_spec'
  gem 'simplecov', require: false
end
