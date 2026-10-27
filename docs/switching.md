# Guarantees and Concurrency

??? abstract "Relevant source files"

    - [`lib/console_kit/tenant_switch.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/tenant_switch.rb)
    - [`lib/console_kit/tenant_rollback.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/tenant_rollback.rb)
    - [`lib/console_kit/tenant_state.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/tenant_state.rb)
    - [`lib/console_kit/instrumentation.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/instrumentation.rb)
    - [`lib/console_kit/errors.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/errors.rb)
    - [`lib/console_kit/connections/base_connection_handler.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/connections/base_connection_handler.rb)
    - [`lib/console_kit/connections/sql_connection_handler.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/connections/sql_connection_handler.rb)
    - [`lib/console_kit/connections/redis_connection_handler.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/connections/redis_connection_handler.rb)
    - [`spec/support/shared_contexts/interleaved_switch.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/spec/support/shared_contexts/interleaved_switch.rb)

{% include-markdown "../README.md" start="<!-- site:guarantees -->" end="<!-- site:programmatic-api -->" %}

{% include-markdown "../README.md" start="<!-- site:concurrency -->" end="<!-- site:console-usage -->" %}
