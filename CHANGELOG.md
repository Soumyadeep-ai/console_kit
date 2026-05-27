# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/).

---

## [2.0.0] - 2026-05-27

### Added
- **Fiber-local context isolation** (`ConsoleKit::Context`) — stack-based tenant context using `Fiber.current` storage; safe for concurrent Rails requests and nested switching.
- **`ConsoleKit.with(:tenant)` block API** — scoped tenant switching that restores the previous tenant automatically, even on exception. Nestable.
- **`ConsoleKit::SwitchPipeline`** — self-registering step pipeline replaces `TenantOrchestrator`. Steps: EnvResolver → SafeguardCheck → TenantSelector → BeforeHooks → TenantConfigurator → ShardConnector → PromptApplier → AfterHooks.
- **Lifecycle hooks** — `config.before_switch` and `config.after_switch` with `on_error: :abort` (veto switch) or `on_error: :warn` (log and continue).
- **ENV override** — `CONSOLE_KIT_TENANT=tenant_one rails c` skips the interactive prompt.
- **Production safeguards** — configurable `production_environments`, `protected_tenants`, and `confirm_dangerous_context` prompt.
- **Rails-native sharding** — `config.use_rails_sharding = true` wraps `ActiveRecord::Base.connected_to` on each tenant switch (Rails 6.1+).
- **`ConsoleKit.status`** — runtime introspection: current tenant, configuration state, environment, shard.
- **`ConsoleKit::TenantResolver`** — convention-over-config: configure `tenants` as a `Hash` (default), `Array` (keys + resolver proc), or `:dynamic` (unbounded proc-based resolution).
- **`ConsoleKit::Benchmarker`** — opt-in per-step timing and memory delta reporting via `config.benchmark = true`.
- **Doctor system** — `rails console_kit:doctor` validates configuration with 8 health checks: tenants configured, keys unique, context class resolvable, required constants present, adapter supported, sharding compatible, hook arity valid, history path writable.
- **Fuzzy tenant selection** via `tty-prompt` with recent tenant memory (`config.recent_tenant_limit`).
- **IRB/Pry prompt** shows `[tenant][env]` after each switch.
- **`ConsoleKit::HookRegistry`** — programmatic hook registration with `hooks_for(event)` accessor.
- **`ConsoleKit::ScopedSwitcher`** — default and sharded variants for block-scoped switching.

### Changed
- **Architecture rewrite** — unified `ConsoleKit::Context` replaces scattered `Thread.current` calls. `SwitchPipeline` replaces `TenantOrchestrator`. All hardcoded values moved to `Configuration`.
- **Backward-compatible public API** — `ConsoleKit.current_tenant`, `ConsoleKit.tenants`, `ConsoleKit.context_class`, `ConsoleKit.reset_current_tenant`, `Setup`, `TenantOrchestrator`, `TenantConfigurator`, `TenantSelector` all preserved as shims.
- Version bumped to `2.0.0`.
- Ruby >= 3.1.0 required (no upper bound — forward-compatible via runtime fiber capability check).
- `tty-prompt ~> 0.23` added as runtime dependency.

### Fixed
- Double-push bug in scoped switcher — `TenantConfigurator` now skips `Context.push` when switcher already pushed the tenant.

---

## [0.1.3] - 2025-08-12
### Added
- `ConsoleKit.current_tenant` method to retrieve the current tenant at runtime.
- `ConsoleKit.reset_current_tenant` to reset tenant selection.
- `pretty_output` configuration added with ability to manually toggle CLI verbosity.

### Changed
- Refactored internal logic for improved maintainability and future extensibility.
- Enhanced test coverage for better reliability and edge case handling.

---

## [0.1.2] - 2025-07-23
### Added
- Changelog added.
- Readme and installation instructions added.

---

## [0.1.1] - 2025-07-21
### Added
- Initial generator: `console_kit:install` to scaffold configuration.
- RSpec test suite to support core features.

### Changed
- Applied RuboCop fixes for code consistency and style.

---

## [0.1.0] - 2025-07-09

- Initial release

### Added
- Core setup logic for ConsoleKit:
  - `ConsoleKit.setup`
  - Tenant selection via CLI.
  - Tenant-specific database configuration.
  - Colorized console output for improved UX.

---

## [Unreleased]

[0.1.3]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.3
[0.1.2]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.2
[0.1.1]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.1
[0.1.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.0
