# Writing a Backend Handler

Every backend ConsoleKit switches is a subclass of
`ConsoleKit::Connections::BaseConnectionHandler` that registers itself with `backend`. The four
built-in handlers are written exactly this way (see [Backends](backends.md)). A handler of your own
gets the same transaction, rollback, verification, validation, console output and dashboard row.

??? abstract "Relevant source files"

    - [`lib/console_kit/connections/base_connection_handler.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/connections/base_connection_handler.rb)
    - [`lib/console_kit/connections/connection_manager.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/connections/connection_manager.rb)
    - [`lib/console_kit/connections/sql_connection_handler.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/connections/sql_connection_handler.rb)
    - [`lib/console_kit/connections/diagnostic_helpers.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/connections/diagnostic_helpers.rb)
    - [`lib/console_kit/connections/dashboard.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/connections/dashboard.rb)
    - [`spec/support/shared_examples/connection_handler_contract.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/spec/support/shared_examples/connection_handler_contract.rb)
    - [`spec/support/shared_contexts/connection_handler_contracts.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/spec/support/shared_contexts/connection_handler_contracts.rb)


## Minimal handler

```ruby
class CacheNamespaceHandler < ConsoleKit::Connections::BaseConnectionHandler
  backend :cache_namespace,
          display_name: 'Cache namespace',            # used in messages and the dashboard
          context_attribute: :tenant_cache_namespace, # writer ConsoleKit calls on context_class
          constants_key: :cache_namespace,            # key read from each tenant's constants
          detail_label: 'Cache NS'                    # label in `tenant_info`

  class << self
    # Validates the configured value, both in `validate!` and in `prepare`. Return a reason or nil.
    def target_error(value) = identifier_error(value)
  end

  def available? = defined?(MyCache) ? true : false

  def prepare(target)
    validate_target!(target)
  end

  def snapshot = MyCache.namespace

  def connect!(target)
    MyCache.namespace = target&.to_s
  end

  def verify!(target)
    actual = MyCache.namespace
    raise verification_error(target&.to_s, actual) unless actual == target&.to_s
  end

  def restore(snapshot)
    MyCache.namespace = snapshot
  end

  private

  def basic_diagnostics
    { name: display_name, status: :connected, latency_ms: nil, details: { namespace: MyCache.namespace } }
  end

  def full_diagnostics = basic_diagnostics
end
```

The handler is registered when the class body runs. Load it before the console starts, for example
by requiring it from `config/initializers/console_kit.rb`. Then add `cache_namespace:` to your
tenants' constants and give your context class a `tenant_cache_namespace=` writer.

## The contract

| Method | Required | Rules |
|---|---|---|
| `available?` | yes | Return a boolean and never raise. It is also called on an instance built with a `nil` context (`ContextWrapper`), so do not touch `context` here. |
| `snapshot` | yes | Capture everything `restore` needs. Must not change anything. |
| `connect!(target)` | yes | Point the backend at `target`. `nil` means reset to your default. |
| `restore(snapshot)` | yes | Undo `connect!` from a snapshot. It may run after a failed `connect!`, so tolerate a half-applied state. |
| `basic_diagnostics` / `full_diagnostics` | yes, private | Return `{ name:, status:, latency_ms:, details: {} }`. |
| `prepare(target)` | no | Reject a target you cannot apply by raising a `ConsoleKit::Error` subclass, and change nothing. It runs before any snapshot is taken. |
| `verify!(target)` | no | Read the live state back and raise `verification_error(expected, actual)` on mismatch. The default does nothing, so the switch is never verified. |
| `unavailable_reason` | no | Return a String to have an unavailable handler reported as *dropped* (warned about and recorded on the tenant state) instead of silently skipped. |
| `diagnostic_identity` | no | A value that changes when the live connection changes. It invalidates the cached `:full` dashboard row. |
| `target_error(value)` (class method) | no | Return a reason String for an invalid constant, or nil. `identifier_error` (non-blank String or Symbol) is available as a helper. |

A required method left unimplemented raises `NotImplementedError`:

- From `available?`: the handler is dropped with a warning and recorded as a dropped backend.
- From `snapshot`: the switch fails before anything is applied.
- From `connect!`: the switch fails and is rolled back.
- From `restore`: the failure is reported as a rollback failure.

The shared RSpec examples in `spec/support/shared_examples/connection_handler_contract.rb`
(`it_behaves_like 'a connection handler'`) encode these rules. For example, `prepare` and `snapshot`
must not change anything. Use them as a checklist.

## Registration rules

Enforced by `HandlerRegistry` in `base_connection_handler.rb`:

- **One handler per backend key.** A second class claiming the same key replaces the first. A warning
  prints and `console_kit.handler_collision` is incremented. Re-declaring the same class (for example
  on `reload!`) is silent.
- **One backend per context attribute.** Claiming an attribute another backend already uses raises
  `ConfigurationError` immediately. Two backends cannot share one slot on the context object.
- **Subclassing does not register.** A subclass that does not call `backend` itself inherits its
  parent's metadata but is not registered, so it cannot displace the parent.

Handlers run in registration order: the four built-ins (SQL, MongoDB, Redis, Elasticsearch), then
yours. Rollback restores them in reverse order.

Your `constants_key` is automatically recognised by `validate!`. It does not trigger an
"unrecognised key" warning, and the cross-tenant coverage and context-writer checks apply to it.

## Testing

`ConsoleKit::Connections::BaseConnectionHandler.unregister(MyHandler)` removes a handler from the
registry, which is useful in test teardown.
