# frozen_string_literal: true
require "json"
require "fileutils"
require "securerandom"
require "time"
require_relative "config"

module Geo
  # Private, bounded run records. Credential headers never enter this interface.
  class Diagnostics
    RETENTION = 7 * 86_400
    MAX_BYTES = 200 * 1024 * 1024

    def initialize(directory, retention: RETENTION, max_bytes: MAX_BYTES, clock: -> { Time.now })
      @directory = File.join(directory, "diagnostics")
      @retention, @max_bytes, @clock = retention, max_bytes, clock
      @mutex, @active = Mutex.new, {}
      FileUtils.mkdir_p(@directory, mode: 0700)
      File.chmod(0700, @directory)
    rescue SystemCallError, IOError
      @unavailable = true
    end

    def start(metadata, redact = nil)
      run = Run.new(self, SecureRandom.hex(16), @clock.call, redact)
      @mutex.synchronize { @active[run.id] = true }
      run.record("start", metadata)
      run
    end

    def path(id)
      raise Error.new("invalid_run", "检索记录编号无效。", 400) unless id.is_a?(String) && id.match?(/\A[a-f0-9]{32}\z/)
      File.join(@directory, "#{id}.jsonl")
    end

    def prune(required = 0)
      files = Dir.glob(File.join(@directory, "*.jsonl")).map { |file| [file, File.mtime(file), File.size(file)] }.sort_by { |row| row[1] }
      total = files.sum { |row| row[2] }
      files.each do |file, modified, size|
        next if @active[File.basename(file, ".jsonl")]
        next unless modified < @clock.call - @retention || total + required > @max_bytes
        File.unlink(file)
        total -= size
      end
      total
    end

    def write(id, type, data)
      return false if @unavailable
      line = JSON.generate("event" => type, "at" => @clock.call.iso8601(3), "data" => data) + "\n"
      @mutex.synchronize do
        return false if prune(line.bytesize) + line.bytesize > @max_bytes
        File.open(path(id), File::WRONLY | File::APPEND | File::CREAT, 0600) { |file| file.write(line) }
      end
      true
    rescue SystemCallError, IOError, JSON::JSONError
      false
    end

    def release(id)
      @mutex.synchronize { @active.delete(id) }
    end

    def available?(id)
      return false if @unavailable
      @mutex.synchronize do
        prune
        File.file?(path(id))
      end
    rescue SystemCallError, IOError
      false
    end

    def read(id)
      file = path(id)
      @mutex.synchronize do
        prune
        raise Error.new("run_not_found", "该检索记录已过期或暂未留存。", 404) unless File.file?(file)
        events = File.readlines(file).map { |line| JSON.parse(line) }
        { "run_id" => id, "events" => events, "complete" => events.last && events.last["event"] == "finish" && events.last["data"]["complete"] }
      end
    rescue JSON::ParserError, SystemCallError, IOError
      raise Error.new("run_unavailable", "检索记录暂时无法读取。", 503)
    end

    class Run
      attr_reader :id
      def initialize(owner, id, created, redact)
        @owner, @id, @created, @redact = owner, id, created, redact
        @complete, @closed, @calls = true, false, []
      end

      def record(type, data)
        @complete = false unless @owner.write(@id, type, @redact ? @redact.call(data) : data)
      end

      def call(data)
        @calls << data.reject { |key, _| %w[request response].include?(key) }
        record("upstream", data)
      end

      def finish(status)
        return if @closed
        record("finish", { "status" => status, "complete" => @complete })
        @closed = true
        @owner.release(@id)
      end

      def summary
        { "available" => @owner.available?(@id), "complete" => @complete,
          "expires_at" => (@created + Diagnostics::RETENTION).iso8601,
          "calls" => @calls, "settled_cny" => @calls.sum { |call| call["settled_micros"].to_i } / 1_000_000.0,
          "pending_cny" => @calls.select { |call| call["charge_id"] && call["settled_micros"].nil? }.sum { |call| call["reserved_micros"] } / 1_000_000.0 }
      end
    end
  end

  class MemoryDiagnostics < Diagnostics
    class MemoryRun < Run
      def summary
        super.merge("storage" => "memory", "expires_at" => @owner.expires_at.iso8601)
      end
    end
    attr_reader :expires_at

    def initialize(max_bytes: 2 * 1024 * 1024)
      @max_bytes, @bytes, @records, @active, @mutex, @clock = max_bytes, 0, {}, {}, Mutex.new, -> { Time.now }
      @expires_at = Time.now + 3600
    end

    def start(metadata, redact = nil)
      run = MemoryRun.new(self, SecureRandom.hex(16), @clock.call, redact)
      @mutex.synchronize { @active[run.id] = true }
      run.record("start", metadata)
      run
    end

    def write(id, type, data)
      line = JSON.generate("event" => type, "at" => @clock.call.iso8601(3), "data" => data)
      @mutex.synchronize do
        @records.keys.each do |old|
          break if @bytes + line.bytesize <= @max_bytes
          next if @active[old]
          @bytes -= @records.delete(old).sum(&:bytesize)
        end
        return false if @bytes + line.bytesize > @max_bytes
        (@records[id] ||= []) << line
        @bytes += line.bytesize
      end
      true
    rescue JSON::JSONError
      false
    end

    def available?(id)
      @mutex.synchronize { @records.key?(id) }
    end

    def read(id)
      raise Error.new("invalid_run", "检索记录编号无效。", 400) unless id.match?(/\A[a-f0-9]{32}\z/)
      @mutex.synchronize do
        raise Error.new("run_not_found", "当前连接没有这条记录，或记录已清理。", 404) unless @records.key?(id)
        events = @records[id].map { |line| JSON.parse(line) }
        { "run_id" => id, "events" => events, "complete" => events.last && events.last["event"] == "finish" && events.last["data"]["complete"] }
      end
    end
  end
end
