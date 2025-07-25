# frozen_string_literal: true

require_relative 'lib/console_kit/version'

Gem::Specification.new do |spec|
  spec.name = 'console_kit'
  spec.version = ConsoleKit::VERSION
  spec.authors = ['Soumyadeep Pal']
  spec.email = ['soumyadeeppal2001@gmail.com']

  spec.summary = 'Toolkit for enhancing Rails console: multi-tenancy.'
  spec.description = 'Adds tenant selection to Rails consoles'
  spec.homepage = 'https://github.com/Soumyadeep-ai/console_kit'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/Soumyadeep-ai/console_kit'
  spec.metadata['changelog_uri'] = 'https://github.com/Soumyadeep-ai/console_kit/blob/main/CHANGELOG.md'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_dependency 'mongoid'
  spec.add_dependency 'rails', '>= 7.2.1'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
