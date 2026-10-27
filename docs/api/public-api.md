# Public API Reference

Everything an application or console user is expected to call. Usage examples and failure semantics
are under [Programmatic API](../usage.md#programmatic-api) and
[Observability](../switching.md#observability). This page is the complete list.

??? abstract "Relevant source files"

    - [<code>lib/<wbr>console_kit.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit.rb)
    - [<code>lib/<wbr>console_kit/<wbr>configuration.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/configuration.rb)
    - [<code>lib/<wbr>console_kit/<wbr>tenant_switch.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/tenant_switch.rb)
    - [<code>lib/<wbr>console_kit/<wbr>tenant_state.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/tenant_state.rb)
    - [<code>lib/<wbr>console_kit/<wbr>console_helpers.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/console_helpers.rb)
    - [<code>lib/<wbr>console_kit/<wbr>instrumentation.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/instrumentation.rb)
    - [<code>lib/<wbr>console_kit/<wbr>diagnostics.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/diagnostics.rb)
    - [<code>lib/<wbr>console_kit/<wbr>errors.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/errors.rb)


## `ConsoleKit`

`lib/console_kit.rb`

| Method | Returns | Notes |
|---|---|---|
| `configure { \|config\| ... }` | block value | Yields the `Configuration`. See [Configuration](../guides/configuration.md). |
| `configuration` | `Configuration` | Memoized, process-wide. |
| `reset_configuration!` | | Drops the configuration and clears this thread's tenant state. |
| `tenants` | Hash or `nil` | Same as `configuration.tenants`. |
| `switch_tenant(key)` | `TenantState` | Transactional switch. Raises on failure. `key` must match a tenant key exactly. |
| `with_tenant(key) { ... }` | block value | Switches, runs the block, and always restores the previous tenant. If the block raised and the restore also fails, the restore failure is printed and the block's exception propagates. |
| `verify_tenant!` | `TenantState` | Re-verifies every available backend against the current tenant. Raises `ConfigurationError` when no tenant is set and `ConnectionVerificationError` on mismatch. Never rolls back. Warns, and counts `console_kit.incomplete_verification`, when some backends were dropped. |
| `current_tenant` | key or `nil` | This thread's tenant. |
| `reset_current_tenant` | | **Interactive:** re-runs tenant selection, the same as the console `switch_tenant` helper. Choosing "none" clears the tenant. |
| `enable_pretty_output` / `disable_pretty_output` | | Set `configuration.pretty_output`. |

## Console helpers

Mixed into the console session by the Railtie (`lib/console_kit/console_helpers.rb`).

| Helper | Does |
|---|---|
| `switch_tenant` | Interactive re-selection. Takes **no** argument, unlike `ConsoleKit.switch_tenant(key)`. |
| `tenant_info` | Prints the current tenant's constants using each handler's `detail_label`. |
| `tenants` | Prints and returns the configured tenant keys. |
| `dashboard(level: :basic)` | Prints the connection dashboard. `:full` adds latency and server details. |

The prompt shows `[tenant_key]` or `[no-tenant]` in both IRB and Pry.

## Console output

Every message ConsoleKit prints starts with `[ConsoleKit]` and has a type (`lib/console_kit/output.rb`):

| Type | Marker | Colour | Used for |
|---|---|---|---|
| success | `[✓]` | bold green | `Tenant initialized: ...` |
| error | `[✗]` | bold red | failures, the production warning |
| warning | `[!]` | bold yellow | dropped backends, isolation warnings, staging |
| header | `--- text ---` | bold blue | the selection menu, dashboard title |
| prompt | none | bold cyan | `Selection (number or name) [1]:` (no newline) |
| trace | none | dim grey | backtraces, timestamped |
| info | none | default | connection progress such as `Switching to Redis DB: 1` |

With `pretty_output = false` the colour codes are dropped and the markers stay, which keeps logs
readable. `Output.silence { ... }` suppresses everything, and is how `reload!` re-applies a tenant
quietly.

## Errors

`lib/console_kit/errors.rb`. Rescue `ConsoleKit::Error` to catch all of them.

```
StandardError
└── ConsoleKit::Error
    ├── ConfigurationError
    │   └── TenantNotFoundError
    ├── UnsupportedBackendError
    ├── ConnectionError              #backend #tenant #operation
    │   └── ConnectionVerificationError  #expected #actual
    ├── RollbackError                #failures => [{ backend:, error: }]
    └── TenantSwitchError            #from_tenant #to_tenant #backend
                                     #original_error #rollback_failures
                                     #rollback_succeeded?
```

| Raised | When |
|---|---|
| `TenantNotFoundError`, `ConfigurationError`, `UnsupportedBackendError` | A switch is rejected before anything changes: unknown tenant, malformed constants, or a backend that cannot honour the target. |
| `TenantSwitchError` | A switch failed after it started (snapshot, apply, connect or verify) and a rollback was attempted. `original_error` holds the cause. |
| `ConnectionVerificationError` | `verify_tenant!` found a backend on the wrong target. Inside a switch, the same error is wrapped in `TenantSwitchError`. |
| `RollbackError` | `with_tenant` could not fully restore the outer tenant after a block that completed normally. |

Error messages pass through `DiagnosticHelpers.scrub`, which redacts URLs with credentials,
`password=…`/`token: …` style assignments, auth headers and user names.

## Instrumentation

`lib/console_kit/instrumentation.rb`

| Method | Does |
|---|---|
| `subscribe { \|name, duration_ms, payload\| ... }` | Receives every **instrumented** event below. A subscriber that raises is ignored. |
| `counts` | A thread-safe copy of `{ event_name => count }`. Covers instrumented events and counters. |
| `clear!` | Removes subscribers and resets counts. Intended for tests. |

**Instrumented events.** These are timed, delivered to subscribers and counted. The payload always
includes `status:` (`:ok` or `:error`), plus `error:` (the class name) on failure.

| Event | Payload |
|---|---|
| `console_kit.tenant_switch` | `tenant:`, `from:` |
| `console_kit.backend_connect` | `backend:`, `tenant:` |
| `console_kit.backend_verify` | `backend:`, `tenant:` (also emitted by `verify_tenant!`) |
| `console_kit.diagnostics` | `backend:`, `level:` |

**Counters.** These are counted only and are not delivered to subscribers.

| Counter | Incremented when |
|---|---|
| `console_kit.rollback` | A rollback starts. |
| `console_kit.rollback_failure` | Each component that failed to restore. |
| `console_kit.verification_failure` | A backend failed `verify!` during a switch or `verify_tenant!`. |
| `console_kit.handler_dropped` | A registered handler was skipped as broken or unavailable with a reason. |
| `console_kit.handler_collision` | Two handler classes claimed the same backend key. |
| `console_kit.incomplete_verification` | `verify_tenant!` passed but some backends were dropped. |
| `console_kit.diagnostics_timeout` | A diagnostics check took longer than its timeout budget. |
| `console_kit.sql_frame_reasserted` | ConsoleKit re-applied a SQL shard that a host `connected_to` block had removed. |

## Lower-level entry points

Stable enough to call, but most code should not need them.

| Call | Use |
|---|---|
| `ConsoleKit::Diagnostics.run(level: :basic, timeout: 2)` | Diagnostics rows as data, for example for your own health output. `clear_cache!` drops this thread's cache. |
| `ConsoleKit::Output.silence { ... }` | Suppresses ConsoleKit output in the block. Fiber-local (`Thread.current[]`). |
| `ConsoleKit::Connections::BaseConnectionHandler` | Base class for your own backend. See [Writing a Backend Handler](../guides/custom-backend-handler.md). |

## Deprecated (removed in 2.0)

Each prints a one-time warning naming its replacement (`lib/console_kit/setup.rb`):

| Deprecated | Use instead |
|---|---|
| `ConsoleKit::Setup.setup` / `.reapply` / `.auto_select?` | `TenantOrchestrator.run` / `.reapply` / `.auto_select?` |
| `ConsoleKit::Setup.current_tenant`, `.tenant_setup_successful?` | `ConsoleKit.current_tenant` |
| `ConsoleKit::Setup.current_tenant=` | `ConsoleKit.switch_tenant` |
| `ConsoleKit::Setup.reset_current_tenant` | `ConsoleKit.reset_current_tenant` |
| `ConsoleKit.pretty_output`, `.context_class`, `.show_dashboard` and their writers, `ConsoleKit.tenants=` | `ConsoleKit.configuration.<name>` |
| `Configuration#validate` | `Configuration#validate!` |
