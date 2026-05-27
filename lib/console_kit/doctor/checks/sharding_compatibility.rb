# lib/console_kit/doctor/checks/sharding_compatibility.rb
# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Doctor
    module Checks
      # Checks that Rails sharding is only enabled on Rails >= 6.1.
      class ShardingCompatibility < Base
        MIN_RAILS_VERSION = '6.1'

        def call
          return pass('sharding disabled') unless config.use_rails_sharding
          return error("Rails sharding requires Rails >= #{MIN_RAILS_VERSION}") unless rails_version_sufficient?

          pass('sharding compatible')
        end

        private

        def rails_version_sufficient?
          return false unless defined?(Rails::VERSION::STRING)

          Gem::Version.new(Rails::VERSION::STRING) >= Gem::Version.new(MIN_RAILS_VERSION)
        end
      end
    end
  end
end
