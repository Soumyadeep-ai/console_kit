# frozen_string_literal: true

require 'fileutils'

module ConsoleKit
  # Maintains a time-ordered history of recently-used tenants with atomic writes.
  class TenantHistory
    def initialize(path, limit)
      @path  = File.expand_path(path)
      @limit = limit
    end

    def recent
      return [] unless File.exist?(@path)

      File.readlines(@path).map(&:chomp).reject(&:empty?).first(@limit)
    end

    def record(tenant)
      sanitized = tenant.to_s.gsub(/[\r\n]/, '_')
      entries   = ([sanitized] + recent).uniq.first(@limit)
      write_atomic("#{entries.join("\n")}\n")
    rescue Errno::EACCES, Errno::ENOENT
      nil
    end

    private

    def write_atomic(content)
      tmp = "#{@path}.tmp.#{Process.pid}"
      File.write(tmp, content)
      File.rename(tmp, @path)
    ensure
      FileUtils.rm_f(tmp)
    end
  end
end
