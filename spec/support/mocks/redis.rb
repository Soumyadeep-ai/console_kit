# frozen_string_literal: true

# Mock for the Redis client to support testing
class Redis
  def self.current; end
  def ping; end
  def info; end
  def select(*); end
end
