# frozen_string_literal: true

# Mock for Mongoid module to support testing
module Mongoid
  def self.override_database(*); end
  def self.default_client; end

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
