# frozen_string_literal: true

module ConsoleKit
  module Connections
    # Everywhere the Elasticsearch index-name prefix lives: `.global` wraps the
    # PROCESS-WIDE `Elasticsearch::Model.index_name_prefix`, while `.current` /
    # `.record` note what each live thread asked for. The note provides no
    # isolation - it exists so disagreeing threads can be detected and reported.
    # `Thread.current[:console_kit_elasticsearch_prefix]` is kept in sync purely
    # as a backward-compatible read path.
    class ElasticsearchPrefixRegistry
      THREAD_KEY = :console_kit_elasticsearch_prefix
      REPORTED_KEY = :console_kit_elasticsearch_prefix_conflict

      UPPERCASE = /[[:upper:]]/
      LEADING = /\A[_\-+]/
      WHITESPACE = /\s/
      ILLEGAL = %r{[\\/*?"<>|,#]}

      class << self
        # nil or a blank prefix means "use the default" and is always valid.
        def prefix_error(prefix)
          return if prefix.nil?
          return 'must be lowercase' if prefix.match?(UPPERCASE)
          return 'must not begin with _, - or +' if prefix.match?(LEADING)
          return 'must not contain whitespace' if prefix.match?(WHITESPACE)

          'must not contain \\ / * ? " < > | , or #' if prefix.match?(ILLEGAL)
        end

        def model = defined?(Elasticsearch::Model) ? Elasticsearch::Model : nil
        def settable? = model.respond_to?(:index_name_prefix=)
        def readable? = model.respond_to?(:index_name_prefix)
        def global = readable? ? model.index_name_prefix.presence&.to_s : nil

        def global=(prefix)
          model.index_name_prefix = prefix if settable?
        end

        # Prunes like every other entry point: a Thread key pins that thread's
        # thread-locals, so a dead thread's note must not survive.
        def current
          synchronize do
            prune
            entries[Thread.current]
          end
        end

        def record(prefix)
          synchronize do
            prune
            prefix.nil? ? entries.delete(Thread.current) : (entries[Thread.current] = prefix)
            Thread.current[THREAD_KEY] = prefix
          end
        end

        def conflicts(prefix)
          synchronize do
            prune
            entries.reject { |thread, held| thread.equal?(Thread.current) || held == prefix }.values.uniq
          end
        end

        # So repeated switches against an unchanged set of threads report once.
        def unreported_conflicts(prefix)
          others = conflicts(prefix)
          signature = [prefix, others]
          return [] if others.empty? || Thread.current[REPORTED_KEY] == signature

          Thread.current[REPORTED_KEY] = signature
          others
        end

        private

        def entries = @entries ||= {}
        def mutex = @mutex ||= Mutex.new
        def synchronize(&) = mutex.synchronize(&)
        def prune = entries.select! { |thread, _| thread.alive? }
      end
    end
  end
end
