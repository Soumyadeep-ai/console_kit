# frozen_string_literal: true

# Stateful fakes backing the Elasticsearch connection handler specs.
module ElasticsearchMocks
  # Fake cluster API. Counts calls so specs can prove :basic diagnostics
  # perform no network work.
  class Cluster
    attr_reader :health_calls

    def initialize(name: 'test-cluster', status: 'green')
      @name = name
      @status = status
      @health_calls = 0
    end

    def health
      @health_calls += 1
      { 'cluster_name' => @name, 'status' => @status }
    end
  end

  # Fake Elasticsearch client exposing #ping and #cluster.
  class Client
    attr_reader :ping_calls, :cluster

    def initialize(cluster: Cluster.new, ping_error: nil)
      @cluster = cluster
      @ping_error = ping_error
      @ping_calls = 0
    end

    # Returns the call count rather than a boolean; the handler only cares
    # that this does not raise.
    def ping
      raise @ping_error if @ping_error

      @ping_calls += 1
    end
  end
end

# Mock for Elasticsearch module to support testing
module Elasticsearch
  # Mock for Elasticsearch::Model: one process-wide, settable and readable
  # index name prefix, mirroring the real library.
  module Model
    class << self
      attr_accessor :index_name_prefix
      attr_writer :client

      def client = @client ||= ElasticsearchMocks::Client.new
    end
  end

  # Variant of Elasticsearch::Model from a version that cannot set a prefix.
  module ModelWithoutPrefix
    class << self
      def client = ElasticsearchMocks::Client.new
    end
  end

  # Variant whose prefix can be written but never read back: a setter with no
  # matching reader.
  module ModelWithWriteOnlyPrefix
    class << self
      attr_writer :index_name_prefix

      def client = ElasticsearchMocks::Client.new
    end
  end
end

# Stable handle on the real mock module so specs can reset it even while
# `stub_const`/`hide_const` is swapping `Elasticsearch::Model` out.
module ElasticsearchMocks
  MODEL = Elasticsearch::Model

  class << self
    def reset!
      MODEL.index_name_prefix = nil
      MODEL.client = nil
    end
  end
end
