# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/).

---

## [1.0.0] - 2026-03-01
### Added
- **Rails `reload!` support:** `context_class` is now resolved dynamically (using strings/symbols) and automatically reapplied via Rails `to_prepare` hook.
- **Configurable SQL Base Class:** Added `sql_base_class` to configuration (defaults to `ApplicationRecord`).
- **Silent Re-application:** Re-applying tenant configuration (on reload) is now completely silent.
- **Comprehensive Validation:** Added `validate!` to ensure `tenants` and `context_class` are correctly set before startup.
- **Thread-Local Safety:** Restored thread-local storage for configuration and current tenant state to ensure isolation in multi-threaded environments.
- **Enhanced Testing:** Test suite expanded to 268 examples with 100% coverage of new architectural changes.

### Changed
- **Architectural Refactor:** Improved dynamic constant resolution to support Rails reloads while maintaining thread isolation. Added support for namespaced class strings (e.g., `MyModule::ApplicationRecord`).
- **Robust Handler Discovery:** Replaced `descendants` with an explicit registry pattern in `BaseConnectionHandler` to support lazy-loading environments.
- **Improved Input Handling:** `TenantSelector` now correctly handles EOF (`Ctrl+D`) as an abort signal.
- **Cleaner API:** Replaced metaprogrammed accessors with explicit, searchable methods.

### Fixed
- Fixed a bug where `context_class` state was lost after code reloads in the console.
- Fixed potential race conditions by restoring thread-local storage.
- Resolved all RuboCop and Reek code quality warnings.

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

---

## [Unreleased]
### Added
- **Name-based selection:** Users can now select tenants by typing their names (case-insensitive) in addition to index numbers.
- **Session Termination:** Support for `exit` or `quit` commands at the selection prompt to immediately terminate the console session.
- **Enhanced Output API:** Added `Output.print_list` and `Output.print_raw` for cleaner, less repetitive terminal output.
- **Skip Option:** Added an explicit "Skip" option (0) to load without tenant configuration.

### Changed
- **Improved UX:** Redesigned the tenant selection menu for better readability, removing the redundant `[ConsoleKit]` prefix from list items.
- **Interactive Prompts:** Selection prompts now keep the cursor on the same line for a more natural CLI experience.
- **Refined Messaging:** Differentiated between intentional "Skip/Abort" actions and actual selection failures.

[1.0.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v1.0.0
[0.1.5]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.5
[0.1.4]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.4
[0.1.3]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.3
[0.1.2]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.2
[0.1.1]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.1
[0.1.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.0
