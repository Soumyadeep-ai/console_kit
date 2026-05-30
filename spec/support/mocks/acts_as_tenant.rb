# frozen_string_literal: true

module ActsAsTenant
  class << self
    attr_accessor :current_tenant
  end

  self.current_tenant = nil
end
