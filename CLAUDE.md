# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@~/.claude/CLAUDE.md

## Commands

```bash
bundle exec rake          # spec + rubocop (default)
bundle exec rake spec     # tests only
bundle exec rake rubocop  # lint only

bundle exec rspec spec/console_kit/foo_spec.rb        # single file
bundle exec rspec spec/console_kit/foo_spec.rb:42     # single example by line
bundle exec rspec -e "description text"               # single example by name
```

SimpleCov enforces **100% line and branch coverage**. Tests fail if coverage drops.

## Architecture

ConsoleKit is a production-safety Rails console toolkit. Core concern: force tenant selection, guard against writes in wrong environments, and audit all console access.

### Startup Pipeline

`Railtie` hooks into `console.start` → `SwitchPipeline` runs ordered steps via `PipelineContext`. Steps halt pipeline on failure. Flow:

```
WelcomeBanner → PresetApplier → EnvResolver → SafeguardCheck →
TenantSelector → BeforeHooks → TenantConfigurator → ShardConnector →
PromptApplier → AfterHooks → ReadonlyEnforcer → AuditLogWriter → StartupSummary
```

Each step is a `Steps::Base` subclass registered in `StepRegistry` with a priority integer. Adding a new step = subclass + register.

### Key Abstractions

**`Configuration`** (`lib/console_kit/configuration.rb`) — all user-facing settings. `DEFAULTS` hash defines safe values. `presets` enables role-based config overlays (`CONSOLE_KIT_ROLE` env var).

**`Context`** — thread/fiber-local tenant state via `FiberStorage`. `TenantConfigurator` wires tenant constants into the context class at switch time.

**`ScopedSwitcher`** — nestable `ConsoleKit.with(:tenant) { }` blocks; restores prior tenant on exit.

**Connection Handlers** (`lib/console_kit/connections/`) — `BaseConnectionHandler` + per-adapter subclasses (SQL, Mongo, Redis, Elasticsearch, Apartment, ActsAsTenant). Lazy-loaded based on gem availability. Adding a new adapter = subclass `BaseConnectionHandler`, register in the loader.

**Doctor** (`lib/console_kit/doctor/`) — 13 health checks run via `rails console_kit:doctor [--verbose]`. Each check is a standalone class with `call` → returns pass/warn/fail result.

### Multi-version CI

`gemfiles/` contains lockfiles for each Rails/Ruby combo. CI matrix covers Rails 6.1–8.1 × Ruby 3.1–4.0. Run locally with `BUNDLE_GEMFILE=gemfiles/rails_7_1.gemfile bundle exec rspec`.
