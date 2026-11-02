# frozen_string_literal: true

require "sqlite3"
require "digest"
require "securerandom"
require_relative "config"
require_relative "diagnostics"

module Geo
  class Store
    attr_reader :diagnostics
    def initialize(directory, limit: Config::BUDGET_MICROS, initial_spend: 0)
      FileUtils.mkdir_p(directory, mode: 0700)
      @diagnostics = Diagnostics.new(directory)
      @retired_file = File.join(directory, "server-installed")
      @limit, @mutex = limit, Mutex.new
      @db = SQLite3::Database.new(File.join(directory, "geo.sqlite3"))
      @db.busy_timeout = 5000
      @db.execute("PRAGMA journal_mode=WAL")
      @db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS charges (id TEXT PRIMARY KEY, kind TEXT NOT NULL, amount INTEGER NOT NULL, state TEXT NOT NULL, created INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS cache (id TEXT PRIMARY KEY, value TEXT NOT NULL, expires INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, expires INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS requests (id TEXT NOT NULL, created INTEGER NOT NULL);
        CREATE INDEX IF NOT EXISTS requests_by_id ON requests(id, created);
      SQL
      File.chmod(0600, File.join(directory, "geo.sqlite3"))
      transaction do
        if initial_spend.positive? && @db.get_first_value("SELECT COUNT(*) FROM charges").to_i.zero?
          @db.execute("INSERT INTO charges VALUES (?,?,?,?,?)", ["local-verification", "initial", initial_spend, "settled", Time.now.to_i])
        end
      end
    end

    def transaction
      @mutex.synchronize do
        result = nil
        @db.transaction(:immediate) { result = yield }
        result
      end
    end

    def reserve(kind, amount)
      raise ArgumentError, "Invalid reservation" unless amount.is_a?(Integer) && amount.positive?
      transaction do
        raise Error.new("local_retired", "本机付费调用已关闭，请使用网站内测入口。", 503) if File.exist?(@retired_file)
        raise Error.new("billing_halted", "发现计费用量异常，后续调用已暂停，请核对官方账单。", 503) if @db.get_first_value("SELECT id FROM charges WHERE state='anomaly' LIMIT 1")
        used = @db.get_first_value("SELECT COALESCE(SUM(amount),0) FROM charges").to_i
        raise Error.new("budget_exhausted", "本次内测的 50 元额度已到上限，后续调用已暂停。", 402) if used + amount > @limit
        id = SecureRandom.hex(16)
        @db.execute("INSERT INTO charges VALUES (?,?,?,?,?)", [id, kind, amount, "reserved", Time.now.to_i])
        id
      end
    end

    def retire_local!
      transaction do
        used = @db.get_first_value("SELECT COALESCE(SUM(amount),0) FROM charges").to_i
        File.open(@retired_file, "w", 0600) do |file|
          file.write(JSON.generate("target" => "https://www.laoyao.cn/geo/", "initial_spend_micros" => used))
          file.flush
          file.fsync
        end
        used
      end
    end

    def settle(id, amount)
      raise ArgumentError, "Invalid settlement" unless amount.is_a?(Integer) && amount >= 0
      anomaly = transaction do
        reserved = @db.get_first_value("SELECT amount FROM charges WHERE id=?", [id]).to_i
        exceeded = amount > reserved
        @db.execute("UPDATE charges SET amount=?, state=? WHERE id=?", [amount, exceeded ? "anomaly" : "settled", id])
        exceeded
      end
      raise Error.new("price_limit", "本次计费用量超出预留范围，已停止后续调用，请核对官方账单。", 503) if anomaly
    end

    def budget
      @mutex.synchronize do
        used = @db.get_first_value("SELECT COALESCE(SUM(amount),0) FROM charges").to_i
        { "limit_cny" => @limit / 1_000_000.0, "used_cny" => used / 1_000_000.0,
          "remaining_cny" => [@limit - used, 0].max / 1_000_000.0,
          "basis" => "按官方高峰价保守核算，未确认的请求保留预留费用" }
      end
    end

    def cache_get(id)
      @mutex.synchronize do
        row = @db.get_first_row("SELECT value FROM cache WHERE id=? AND expires>?", [id, Time.now.to_i])
        row && JSON.parse(row[0])
      end
    end

    def cache_put(id, data)
      @mutex.synchronize do
        @db.execute("DELETE FROM cache WHERE expires<?", [Time.now.to_i])
        @db.execute("INSERT OR REPLACE INTO cache VALUES (?,?,?)", [id, JSON.generate(data), Time.now.to_i + 900])
      end
    end

    def session_create
      token = SecureRandom.hex(32)
      @mutex.synchronize do
        @db.execute("DELETE FROM sessions WHERE expires<?", [Time.now.to_i])
        @db.execute("INSERT INTO sessions VALUES (?,?)", [Digest::SHA256.hexdigest(token), Time.now.to_i + 43_200])
      end
      token
    end

    def session_valid?(token)
      return false unless token.to_s.match?(/\A[a-f0-9]{64}\z/)
      @mutex.synchronize do
        !@db.get_first_value("SELECT id FROM sessions WHERE id=? AND expires>?", [Digest::SHA256.hexdigest(token), Time.now.to_i]).nil?
      end
    end

    def session_delete(token)
      @mutex.synchronize { @db.execute("DELETE FROM sessions WHERE id=?", [Digest::SHA256.hexdigest(token.to_s)]) }
    end

    def rate_limit(id, limit, window)
      transaction do
        now = Time.now.to_i
        @db.execute("DELETE FROM requests WHERE created<?", [now - 86_400])
        count = @db.get_first_value("SELECT COUNT(*) FROM requests WHERE id=? AND created>?", [id, now - window]).to_i
        raise Error.new("rate_limited", "请求较密集，请稍后再试。", 429) if count >= limit
        @db.execute("INSERT INTO requests VALUES (?,?)", [id, now])
      end
    end

    def close
      @mutex.synchronize { @db.close }
    end
  end
end
