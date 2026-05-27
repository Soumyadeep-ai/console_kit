# frozen_string_literal: true

# Mock for Mongoid module to support testing
module Mongoid
  class << self
    def override_database(*); end
    def override_client(*); end
    def default_client; end
  end

  # Mock for Mongoid::Config
  module Config
    class << self
      def clients = {}
    end
  end

  # Mock for Mongoid Client
  class Client
    def use(*); end
    def database; end
  end

  # Mock for Mongoid Database
  class Database
    def name; end
    def command(*); end
  end
end
