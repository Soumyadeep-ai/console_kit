# frozen_string_literal: true

# Mock for the Redis client to support testing
class Redis
  class << self
    def current; end
  end

  def ping; end
  def info; end
  def select(*); end
end
