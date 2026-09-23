# frozen_string_literal: true

module ElasticsearchMocks
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

  class Client
    attr_reader :ping_calls, :cluster

    def initialize(cluster: Cluster.new, ping_error: nil)
      @cluster = cluster
      @ping_error = ping_error
      @ping_calls = 0
    end

    def ping
      raise @ping_error if @ping_error

      @ping_calls += 1
    end
  end
end

module Elasticsearch
  module Model
    class << self
      attr_accessor :index_name_prefix
      attr_writer :client

      def client = @client ||= ElasticsearchMocks::Client.new
    end
  end

  module ModelWithoutPrefix
    class << self
      def client = ElasticsearchMocks::Client.new
    end
  end

  module ModelWithWriteOnlyPrefix
    class << self
      attr_writer :index_name_prefix

      def client = ElasticsearchMocks::Client.new
    end
  end
end

module ElasticsearchMocks
  MODEL = Elasticsearch::Model

  class << self
    def reset!
      MODEL.index_name_prefix = nil
      MODEL.client = nil
    end
  end
end
