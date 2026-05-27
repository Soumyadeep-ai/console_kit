# frozen_string_literal: true

# Mock for Elasticsearch module to support testing
module Elasticsearch
  # Mock for Elasticsearch::Model to support testing
  module Model
    def self.client; end
    def self.index_name_prefix=(*); end
  end
end
