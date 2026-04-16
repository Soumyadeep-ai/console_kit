# frozen_string_literal: true

module Mongoid
  def self.override_database(*); end
  def self.default_client; end

  class Client
    def use(*); end
    def database; end
  end

  class Database
    def name; end
    def command(*); end
  end
end
