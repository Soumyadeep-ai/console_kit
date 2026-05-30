# frozen_string_literal: true

require 'time'

module ConsoleKit
  # Writes structured audit log entries to a file.
  # File permission errors are caught and surfaced as warnings — never crashes.
  # All field values are sanitized against log injection (newlines, pipes stripped).
  class AuditLogger
    ENTRY_FORMAT = [
      '%<timestamp>s', 'user=%<user>s', 'env=%<env>s',
      'tenant=%<tenant>s', 'action=%<action>s', 'status=%<status>s'
    ].join(' | ')

    def initialize(path)
      @path = File.expand_path(path)
    end

    def log(tenant:, action:, status: :success, env: current_env, user: current_user)
      File.open(@path, 'a') { |f| f.puts(build_entry(tenant, action, status, env, user)) }
    rescue Errno::EACCES, Errno::ENOENT, Errno::EROFS => e
      Output.print_warning("AuditLogger: could not write to #{@path}: #{e.message}")
    end

    private

    def build_entry(tenant, action, status, env, user)
      format(
        ENTRY_FORMAT,
        timestamp: Time.now.iso8601,
        user: sanitize_field(user),
        env: sanitize_field(env),
        tenant: sanitize_field(tenant.to_s),
        action: sanitize_field(action.to_s),
        status: sanitize_field(status.to_s)
      )
    end

    def sanitize_field(value)
      value.to_s.gsub(/[\r\n|]/, '_')
    end

    def current_env
      if defined?(Rails) && Rails.respond_to?(:env)
        Rails.env.to_s
      else
        ENV.fetch('RAILS_ENV', nil) || ENV.fetch('RACK_ENV', nil) || 'development'
      end
    end

    def current_user = ENV.fetch('USER', 'unknown')
  end
end
