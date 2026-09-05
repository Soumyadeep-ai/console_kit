# frozen_string_literal: true

module ConsoleKit
  module Connections
    # Everywhere the Elasticsearch index-name prefix lives.
    #
    # Two storage locations, deliberately kept apart:
    #
    #   * `.global` / `.global=` wrap `Elasticsearch::Model.index_name_prefix`,
    #     the single PROCESS-WIDE attribute the library actually indexes with;
    #   * `.current` / `.record` are a mutex-protected note of the prefix each
    #     live thread asked ConsoleKit for.
    #
    # The per-thread note provides no isolation whatsoever - the last writer to
    # `.global=` wins for every thread. It exists so the handler can *detect*
    # and report threads that disagree instead of letting them silently share
    # indices. `Thread.current[:console_kit_elasticsearch_prefix]` is kept in
    # sync purely as a backward-compatible read path for pre-1.5 callers.
    class ElasticsearchPrefixRegistry
      THREAD_KEY = :console_kit_elasticsearch_prefix
      REPORTED_KEY = :console_kit_elasticsearch_prefix_conflict

      # What makes an index-name prefix legal. Lives here rather than on the
      # handler because this class owns the prefix; the handler's target_error
      # delegates so there is exactly one rule.
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

        # The prefix this thread last asked ConsoleKit for.
        def current = synchronize { entries[Thread.current] }

        def record(prefix)
          synchronize do
            prune
            prefix.nil? ? entries.delete(Thread.current) : (entries[Thread.current] = prefix)
            Thread.current[THREAD_KEY] = prefix
          end
        end

        # Distinct prefixes held by other live threads that differ from `prefix`.
        def conflicts(prefix)
          synchronize do
            prune
            entries.reject { |thread, held| thread.equal?(Thread.current) || held == prefix }.values.uniq
          end
        end

        # Conflicts this thread has not been told about yet, so repeated switches
        # against an unchanged set of threads report once rather than every time.
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
