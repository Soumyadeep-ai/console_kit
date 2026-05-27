# frozen_string_literal: true

# Mock for Elasticsearch module to support testing
module Elasticsearch
  # Mock for Elasticsearch::Model to support testing
  module Model
    class << self
      def client; end
      def index_name_prefix=(*); end
    end
  end
end
