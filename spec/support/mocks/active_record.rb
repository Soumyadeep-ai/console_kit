# frozen_string_literal: true

class ApplicationRecord
  def self.establish_connection(*); end
  def self.connection; end
  def self.connection_pool; end
end
