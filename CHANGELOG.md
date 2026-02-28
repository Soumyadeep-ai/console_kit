# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/).

---

## [1.0.0] - 2026-02-28
### Added
- **Rails `reload!` support:** `context_class` is now resolved dynamically and automatically reapplied via Rails `to_prepare` hook, ensuring tenant state persists after code changes.
- **Process-Global Configuration:** Moved configuration storage to class-level variables to ensure settings persist across threads within a console session while maintaining thread-local tenant context.
- **Explicit Connection Resetting:** Added logic to reset ActiveRecord and Mongoid connections to their default states when clearing or switching tenants.
- **Name-based selection:** Users can now select tenants by typing their names (case-insensitive) in addition to index numbers.
- **Session Termination:** Support for `exit` or `quit` commands at the selection prompt to immediately terminate the console session.
- **Skip Option:** Added an explicit "Skip" option (0) to load without tenant configuration.
- **Comprehensive Validation:** Added strict interface validation for `context_class` (both getters and setters) and type validation for the `tenants` configuration hash.
- **Configurable SQL Base Class:** Added `sql_base_class` configuration option (defaults to `ApplicationRecord`).
- **Enhanced Testing:** Expanded test suite to 271 examples with 100% coverage of new architectural changes and edge cases.

### Changed
- **Architectural Refactor:** Improved dynamic constant resolution and moved to an explicit registry pattern for connection handlers to support lazy-loading environments.
- **Improved UX:** Redesigned the tenant selection menu for better readability and refined terminal output.
- **Robust Input Handling:** `TenantSelector` now correctly handles EOF (`Ctrl+D`) and invalid inputs with a retry mechanism.

### Fixed
- Fixed state loss of `context_class` after Rails code reloads.
- Fixed a critical edge case where database connections remained tied to previous tenants after context clearing.
- Resolved all RuboCop offenses and addressed major Reek code smells.
- Fixed missing `ActiveSupport` dependency for time-based output features.

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

[1.0.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v1.0.0
[0.1.5]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.5
[0.1.4]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.4
[0.1.3]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.3
[0.1.2]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.2
[0.1.1]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.1
[0.1.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.0
