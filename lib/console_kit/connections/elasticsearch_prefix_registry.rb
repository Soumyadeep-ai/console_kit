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

      class << self
        # nil or a blank prefix means "use the default" and is always valid.
        def prefix_error(prefix)
          return unless prefix
          return 'must be lowercase' if prefix.match?(/[[:upper:]]/)
          return 'must not begin with _, - or +' if prefix.match?(/\A[_\-+]/)
          return 'must not contain whitespace' if prefix.match?(/\s/)

          'must not contain \\ / * ? " < > | , or #' if prefix.match?(%r{[\\/*?"<>|,#]})
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
          synchronize { store(Thread.current, prefix) }
        end

        def conflicts(prefix)
          synchronize do
            prune
            entries.reject { |thread, held| thread.equal?(Thread.current) || held == prefix }.values.uniq
          end
        end

        # So repeated switches against an unchanged set of threads report once.
        def unreported_conflicts(prefix)
          thread = Thread.current
          others = conflicts(prefix)
          return [] if others.empty? || thread[REPORTED_KEY] == [prefix, others]

          thread[REPORTED_KEY] = [prefix, others]
          others
        end

        private

        def store(thread, prefix)
          prune
          prefix ? (entries[thread] = prefix) : entries.delete(thread)
          thread[THREAD_KEY] = prefix
        end

        def entries = @entries ||= {}
        def mutex = @mutex ||= Mutex.new
        def synchronize(&) = mutex.synchronize(&)
        def prune = entries.select! { |thread, _prefix| thread.alive? }
      end
    end
  end
end
