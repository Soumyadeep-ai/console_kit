# frozen_string_literal: true

# Mock for ApplicationRecord to support testing
class ApplicationRecord
  class << self 
    def establish_connection(*); end
    def connection; end
    def connection_pool; end
  end
end
