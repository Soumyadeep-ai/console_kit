# frozen_string_literal: true

# Mock for ApplicationRecord to support testing
class ApplicationRecord
  def self.establish_connection(*); end
  def self.connection; end
  def self.connection_pool; end
end
