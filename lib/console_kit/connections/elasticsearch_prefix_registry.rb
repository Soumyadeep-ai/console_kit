# frozen_string_literal: true

module ConsoleKit
  module Connections
    class ElasticsearchPrefixRegistry
      THREAD_KEY = :console_kit_elasticsearch_prefix
      REPORTED_KEY = :console_kit_elasticsearch_prefix_conflict

      class << self
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
