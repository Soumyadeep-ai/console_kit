# Development, Testing and Release

??? abstract "Relevant source files"

    - [`Rakefile`](https://github.com/Soumyadeep-ai/console_kit/blob/master/Rakefile)
    - [`.rubocop.yml`](https://github.com/Soumyadeep-ai/console_kit/blob/master/.rubocop.yml)
    - [`spec/spec_helper.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/spec/spec_helper.rb)
    - [`.github/workflows/test_suite.yml`](https://github.com/Soumyadeep-ai/console_kit/blob/master/.github/workflows/test_suite.yml)
    - [`.github/workflows/release.yml`](https://github.com/Soumyadeep-ai/console_kit/blob/master/.github/workflows/release.yml)
    - [`.github/workflows/docs.yml`](https://github.com/Soumyadeep-ai/console_kit/blob/master/.github/workflows/docs.yml)
    - [`benchmark/support/setup.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/benchmark/support/setup.rb)
    - [`gemfiles/common.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/gemfiles/common.rb)
    - [`console_kit.gemspec`](https://github.com/Soumyadeep-ai/console_kit/blob/master/console_kit.gemspec)
    - [`mkdocs.yml`](https://github.com/Soumyadeep-ai/console_kit/blob/master/mkdocs.yml)

## Setup

```sh
bin/setup          # bundle install
bin/console        # IRB with console_kit loaded (no Rails app, no Railtie)
```

## Everyday commands

| Command | Runs |
|---|---|
| `bundle exec rake` | `spec` then `rubocop`. This is what the CI `rake` job runs. |
| `bundle exec rspec` | The test suite only. |
| `bundle exec rubocop` | Lint (`.rubocop.yml`, with the `rubocop-rspec` and `rubocop-rake` plugins). |
| `bundle exec rake benchmark` | Every `benchmark/NN_*.rb` script (see [Benchmarks](#benchmarks)). |

To run against one Rails version from the CI matrix:

```sh
BUNDLE_GEMFILE=gemfiles/rails_7_1.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_7_1.gemfile bundle exec rspec
```

Each `gemfiles/rails_X_Y.gemfile` pins `activerecord`, `activesupport` and `railties`, then pulls in
the shared development gems from `gemfiles/common.rb`. The root `Gemfile` uses `common.rb` too and
adds `benchmark-ips` in a `:benchmark` group.

## Test suite

No real database, Redis, Mongo or Elasticsearch is needed. Every backend is a stateful fake.

| Path | Contents |
|---|---|
| `spec/console_kit/` | One spec per `lib/console_kit/` file, plus behaviour specs: `switch_sequence`, `rollback_integrity`, `failure_injection`, `nested_tenant`, `concurrency`, `fiber_scope`, `dropped_backend`, `instrumentation_contract`. |
| `spec/console_kit/connections/` | Handler, strategy, registry, dashboard and helper specs. `host_connected_to_spec.rb` covers interaction with an app's own `connected_to` blocks. |
| `spec/console_kit/integration/`, `spec/integration/` | End-to-end lifecycle and full console flow, including the interactive selector driven through a stubbed `$stdin`. |
| `spec/support/mocks/` | Fakes for ActiveRecord, Mongoid, Redis and Elasticsearch. |
| `spec/support/shared_contexts/tenant_backends.rb` | A four-backend fixture (`TenantBackends::TENANTS`) and helpers that read every backend's live identity. |
| `spec/support/shared_contexts/tenant_switch_setup.rb` | Configures ConsoleKit against those fakes, with output silenced. |
| `spec/support/shared_examples/connection_handler_contract.rb` | `it_behaves_like 'a connection handler'`, the contract every handler must satisfy. |

`spec/spec_helper.rb` resets all global and thread-local ConsoleKit state after **every** example:
configuration, `StateStore`, instrumentation, Redis and Elasticsearch registries, and silence flags.
If you add new process-wide or `Thread.current` state, reset it there, or specs will leak into each
other under the random ordering.

Coverage is collected by SimpleCov with branch coverage, grouped as Core, Connections and Generators.

## CI

`.github/workflows/test_suite.yml` runs on pushes and pull requests to `master`:

- **test:** `bundle exec rspec` on Rails 6.1–8.1 × Ruby 3.1–4.0, excluding Rails 8.0 and 8.1 on
  Ruby 3.1. That is 28 jobs, with `fail-fast: false`.
- **rake:** `bundle exec rake` (spec and RuboCop) on Ruby 3.4.

## Release

`.github/workflows/release.yml` runs when a `v*.*.*` tag is pushed. It runs the specs on Ruby 3.4.4,
then builds the gem, creates a GitHub Release with generated notes, and publishes to RubyGems through
Trusted Publishing (no API key).

1. Bump `ConsoleKit::VERSION` in `lib/console_kit/version.rb` and update `CHANGELOG.md`.
2. Merge to `master`.
3. `git tag vX.Y.Z && git push origin vX.Y.Z`

Do not also run `bundle exec rake release`. It would push the gem from your machine, and the
workflow's publish step would then fail on the duplicate version.

## Docs site

The site is built with MkDocs Material from `docs/` (`mkdocs.yml`). `docs/index.md`, `usage.md`,
`switching.md` and `changelog.md` pull their content from `README.md` and `CHANGELOG.md`, using the
`<!-- site:... -->` markers in the README. Edit the README, not those pages. Keep the markers in
place when you move sections around.

```sh
pip install -r docs/requirements.txt
mkdocs serve            # live preview at http://127.0.0.1:8000
mkdocs build --strict   # what CI runs; fails on broken links or anchors
```

`.github/workflows/docs.yml` builds the site on every pull request and deploys it to GitHub Pages
on pushes to `master`.

## Benchmarks

`benchmark/` measures cost against the same kind of stateful fakes (`benchmark/support/`). It never
touches a real service.

| Script | Measures |
|---|---|
| `01_switch_same_tenant.rb` | `TenantConfigurator.configure_tenant` (short-circuits when already current) vs. `ConsoleKit.switch_tenant` (always a full transaction). |
| `02_switch_all_backends.rb` | Switches per second, SQL only vs. all four backends. |
| `03_diagnostics_levels.rb` | Dashboard `:basic` vs. `:full`, cold vs. cached, and the backend calls each makes. Cached calls should add none. |
| `04_pool_churn_counts.rb` | SQL pool disconnects for repeat, different and reset switches, native vs. fallback path. |
| `05_allocations.rb` | Objects allocated per switch, alternating vs. same tenant. |
