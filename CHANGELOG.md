# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/).

---

## [1.2.0] - 2026-03-24
### Added
- **Connection Dashboard:** New `dashboard` console helper displaying a Unicode table with connection status, latency, and service-specific details (adapter, DB version, pool size, memory, cluster health) for all active handlers.
- **`show_dashboard` Config Option:** Opt-in auto-display of the dashboard on tenant switch (`config.show_dashboard = true`). Off by default to keep tenant switching fast.
- **Handler Diagnostics:** Each connection handler now exposes a `diagnostics` method with status, latency, and details.
- **Per-Handler Timeout:** Diagnostics calls are wrapped in a 2-second timeout to prevent slow services from blocking.
- **Rails 6.1+ Support:** Lowered minimum Rails version from 7.2.1 to 6.1, enabling use in older Rails applications.
- **Pry Prompt Fallback:** Graceful fallback for Pry versions < 0.13 that lack `Pry::Prompt.new`.
- **IRB Fallback:** Console helpers now work when `IRB::ExtendCommandBundle` is not available.
- **Multi-version CI:** Test matrix covering Rails 6.1, 7.0, 7.1, 7.2, and 8.0.

### Changed
- **Lightweight Dependencies:** Replaced full `rails` gem dependency with `railties`, `activerecord`, and `activesupport` only.
- **Smaller Gem Package:** Excluded `.md` files and `docs/` from the gem package.

---

## [1.1.0] - 2026-03-14
### Added
- **Redis Connection Handler:** Automatic Redis DB selection per tenant via `Redis.current.select`, with graceful fallback for Redis v5+ where `Redis.current` is deprecated.
- **Elasticsearch Connection Handler:** Sets a per-tenant Elasticsearch index name prefix via thread-local storage and `Elasticsearch::Model.index_name_prefix=` (when available).
- **Console Helpers:** New `switch_tenant`, `tenant_info`, and `tenants` methods available in the Rails console for quick tenant management.
- **Custom Console Prompt:** IRB and Pry prompts now display the active tenant name (e.g., `[acme] main:001>`).
- **Tenant Banner:** On successful tenant initialization, a banner now shows the tenant name, environment safety warnings (production in red, staging in yellow), and a summary of active connections.
- **Environment Safety Warnings:** Production and staging environments are flagged with color-coded warnings at tenant setup time.
- New tenant configuration keys: `redis_db`, `elasticsearch_prefix`, and `environment`.

### Changed
- `TenantConfigurator` now manages `tenant_redis_db` and `tenant_elasticsearch_prefix` context attributes alongside existing ones.
- Generator template updated with examples for the new configuration keys.

---

## [1.0.0] - 2026-03-01
### Added
- **Global Configuration Persistence:** ConsoleKit settings now persist across the entire session and across multiple threads.
- **Isolated Tenant Selection:** Each thread maintains its own tenant selection for safety, while sharing the global configuration.
- **Seamless Rails Reloading:** Full support for Rails `reload!`; your selected tenant and context are now automatically preserved after code reloads.
- **Reliable Tenant Switching:** Switching or clearing tenants now correctly resets all database connections (SQL and MongoDB) to their default state.
- **Flexible Tenant Selection:** Users can now select tenants by typing their names (case-insensitive) in addition to index numbers.
- **Session Control:** Added support for `exit` or `quit` commands directly at the selection prompt to terminate the console session.
- **Safe Mode:** Added a "Skip" option (0) to load the console without any tenant configuration.
- **Improved Configuration Validation:** Enhanced startup checks to provide clearer feedback if the configuration or context class is incorrectly defined.
- **Custom SQL Base Class:** New configuration option to specify a custom base class for SQL connections.

### Changed
- **Modernized CLI Interface:** Redesigned the tenant selection menu and prompts for a cleaner, more intuitive user experience.
- **Enhanced Error Feedback:** Improved messaging for invalid selections and missing configurations.
- **Optimized Performance:** Refactored internal discovery and configuration logic for better reliability in large applications.

### Fixed
- Fixed a bug where tenant context was lost after running `reload!` in the Rails console.
- Fixed an issue where database connections could remain tied to a previous tenant after the context was cleared.
- Resolved all stability and code quality warnings.
- Fixed timestamp formatting in console output.

---

## [0.1.5] - 2025-10-12
### Added
- Minor Bug Fixes

---

## [0.1.4] - 2025-09-30
### Added
- Minor Fixes and Improvements

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

[1.2.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v1.2.0
[1.1.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v1.1.0
[1.0.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v1.0.0
[0.1.5]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.5
[0.1.4]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.4
[0.1.3]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.3
[0.1.2]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.2
[0.1.1]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.1
[0.1.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.0
