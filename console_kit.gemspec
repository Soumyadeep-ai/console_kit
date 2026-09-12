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

  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['changelog_uri'] = 'https://github.com/Soumyadeep-ai/console_kit/blob/main/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # An allowlist, not an exclusion list: only what the gem needs at runtime is
  # packaged, so a new file or directory in the repository cannot quietly end up
  # in the released gem. Tracked files only, so untracked local artefacts and
  # build output are never picked up either.
  spec.files = IO.popen(%w[git ls-files -z -- lib LICENSE.txt], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true)
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'activerecord', '>= 6.1'
  spec.add_dependency 'activesupport', '>= 6.1'
  spec.add_dependency 'railties', '>= 6.1'
end
