# Guarantees and Concurrency

??? abstract "Relevant source files"

    - [<code>lib/<wbr>console_kit/<wbr>tenant_switch.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/tenant_switch.rb)
    - [<code>lib/<wbr>console_kit/<wbr>tenant_rollback.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/tenant_rollback.rb)
    - [<code>lib/<wbr>console_kit/<wbr>tenant_state.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/tenant_state.rb)
    - [<code>lib/<wbr>console_kit/<wbr>instrumentation.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/instrumentation.rb)
    - [<code>lib/<wbr>console_kit/<wbr>errors.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/errors.rb)
    - [<code>lib/<wbr>console_kit/<wbr>connections/<wbr>base_connection_handler.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/connections/base_connection_handler.rb)
    - [<code>lib/<wbr>console_kit/<wbr>connections/<wbr>sql_connection_handler.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/connections/sql_connection_handler.rb)
    - [<code>lib/<wbr>console_kit/<wbr>connections/<wbr>redis_<wbr>connection_<wbr>handler.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/connections/redis_connection_handler.rb)
    - [<code>spec/<wbr>support/<wbr>shared_contexts/<wbr>interleaved_switch.rb</code>](https://github.com/Soumyadeep-ai/console_kit/blob/master/spec/support/shared_contexts/interleaved_switch.rb)

{% include-markdown "../README.md" start="<!-- site:guarantees -->" end="<!-- site:programmatic-api -->" %}

{% include-markdown "../README.md" start="<!-- site:concurrency -->" end="<!-- site:console-usage -->" %}
