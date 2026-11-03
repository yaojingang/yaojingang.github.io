# frozen_string_literal: true

require "sqlite3"
require "digest"
require "securerandom"
require_relative "config"
require_relative "diagnostics"

module Geo
  class Store
    attr_reader :diagnostics
    def initialize(directory, limit: Config::BUDGET_MICROS, initial_spend: 0, memory: false, ledger: nil, expires_at: nil)
      FileUtils.mkdir_p(directory, mode: 0700) unless memory
      @diagnostics = memory ? MemoryDiagnostics.new(expires_at: expires_at) : Diagnostics.new(directory)
      @retired_file = memory ? nil : File.join(directory, "server-installed")
      @limit, @mutex = limit, Mutex.new
      @ledger = ledger
      @cache_limit = memory ? 2 * 1024 * 1024 : nil
      @db = SQLite3::Database.new(memory ? ":memory:" : File.join(directory, "geo.sqlite3"))
      @db.busy_timeout = 5000
      @db.execute("PRAGMA journal_mode=WAL")
      @db.execute("PRAGMA temp_store=MEMORY") if memory
      @db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS charges (id TEXT PRIMARY KEY, kind TEXT NOT NULL, amount INTEGER NOT NULL, state TEXT NOT NULL, created INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS cache (id TEXT PRIMARY KEY, value TEXT NOT NULL, expires INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, expires INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS requests (id TEXT NOT NULL, created INTEGER NOT NULL);
        CREATE INDEX IF NOT EXISTS requests_by_id ON requests(id, created);
        CREATE TABLE IF NOT EXISTS personal_charges (id TEXT PRIMARY KEY, owner TEXT NOT NULL, kind TEXT NOT NULL, amount INTEGER NOT NULL, state TEXT NOT NULL, expires INTEGER NOT NULL);
        CREATE INDEX IF NOT EXISTS personal_charges_by_owner ON personal_charges(owner);
        CREATE INDEX IF NOT EXISTS personal_charges_by_expiry ON personal_charges(expires);
        CREATE TABLE IF NOT EXISTS revoked_personal (owner TEXT PRIMARY KEY, expires INTEGER NOT NULL);
        CREATE INDEX IF NOT EXISTS revoked_personal_by_expiry ON revoked_personal(expires);
      SQL
      File.chmod(0600, File.join(directory, "geo.sqlite3")) unless memory
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
      return @ledger.reserve(kind, amount) if @ledger
      transaction do
        raise Error.new("local_retired", "本机付费调用已关闭，请使用网站内测入口。", 503) if @retired_file && File.exist?(@retired_file)
        raise Error.new("billing_halted", "发现计费用量异常，后续调用已暂停，请核对官方账单。", 503) if @db.get_first_value("SELECT id FROM charges WHERE state='anomaly' LIMIT 1")
        used = @db.get_first_value("SELECT COALESCE(SUM(amount),0) FROM charges").to_i
        raise Error.new("budget_exhausted", "本次使用的保护额度已到上限，后续调用已暂停。", 402) if used + amount > @limit
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
      return @ledger.settle(id, amount) if @ledger
      anomaly = transaction do
        reserved = @db.get_first_value("SELECT amount FROM charges WHERE id=?", [id]).to_i
        exceeded = amount > reserved
        @db.execute("UPDATE charges SET amount=?, state=? WHERE id=?", [amount, exceeded ? "anomaly" : "settled", id])
        exceeded
      end
      raise Error.new("price_limit", "本次计费用量超出预留范围，已停止后续调用，请核对官方账单。", 503) if anomaly
    end

    def budget
      return @ledger.budget if @ledger
      @mutex.synchronize do
        used = @db.get_first_value("SELECT COALESCE(SUM(amount),0) FROM charges").to_i
        { "limit_cny" => @limit / 1_000_000.0, "used_cny" => used / 1_000_000.0,
          "remaining_cny" => [@limit - used, 0].max / 1_000_000.0,
          "basis" => "按官方高峰价保守核算，未确认的请求保留预留费用" }
      end
    end

    def revoke_personal(token, expires)
      transaction do
        @db.execute("DELETE FROM revoked_personal WHERE expires<?", [Time.now.to_i])
        @db.execute("INSERT OR REPLACE INTO revoked_personal VALUES (?,?)", [Digest::SHA256.hexdigest(token), expires])
      end
    end

    def personal_revoked?(token)
      @mutex.synchronize { !!@db.get_first_value("SELECT owner FROM revoked_personal WHERE owner=? AND expires>?", [Digest::SHA256.hexdigest(token), Time.now.to_i]) }
    end

    def personal_transaction
      transaction { yield @db }
    end

    class PersonalLedger
      def initialize(store, token, expires, limit)
        @store, @owner, @expires, @limit = store, Digest::SHA256.hexdigest(token), expires, limit
      end

      def reserve(kind, amount)
        @store.personal_transaction do |db|
          db.execute("DELETE FROM personal_charges WHERE expires<?", [Time.now.to_i - 600])
          if @expires <= Time.now.to_i || db.get_first_value("SELECT owner FROM revoked_personal WHERE owner=?", [@owner])
            raise Error.new("unauthorized", "保存的 Key 已清除或过期，请重新连接。", 401)
          end
          raise Error.new("billing_halted", "发现计费用量异常，后续调用已暂停。", 503) if db.get_first_value("SELECT id FROM personal_charges WHERE owner=? AND state='anomaly'", [@owner])
          used = db.get_first_value("SELECT COALESCE(SUM(amount),0) FROM personal_charges WHERE owner=?", [@owner]).to_i
          raise Error.new("budget_exhausted", "当前个人连接的保护额度已用完，请在连接页核对。", 402) if used + amount > @limit
          id = SecureRandom.hex(16)
          db.execute("INSERT INTO personal_charges VALUES (?,?,?,?,?,?)", [id, @owner, kind, amount, "reserved", @expires])
          id
        end
      end

      def settle(id, amount)
        anomaly = @store.personal_transaction do |db|
          reserved = db.get_first_value("SELECT amount FROM personal_charges WHERE owner=? AND id=?", [@owner, id])
          raise Error.new("invalid_charge", "费用记录暂时无法确认。", 503) if reserved.nil?
          exceeded = amount > reserved.to_i
          db.execute("UPDATE personal_charges SET amount=?,state=? WHERE owner=? AND id=?", [amount, exceeded ? "anomaly" : "settled", @owner, id])
          exceeded
        end
        raise Error.new("price_limit", "计费用量超出预留范围，后续调用已暂停。", 503) if anomaly
      end

      def budget
        @store.personal_transaction do |db|
          used = db.get_first_value("SELECT COALESCE(SUM(amount),0) FROM personal_charges WHERE owner=?", [@owner]).to_i
          { "limit_cny" => @limit / 1_000_000.0, "used_cny" => used / 1_000_000.0, "remaining_cny" => [@limit - used, 0].max / 1_000_000.0,
            "basis" => "当前保存 Key 的独立保护额度，按官方价格保守记录" }
        end
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
        if @cache_limit
          while @db.get_first_value("SELECT COALESCE(SUM(length(CAST(value AS BLOB))),0) FROM cache").to_i > @cache_limit
            @db.execute("DELETE FROM cache WHERE id=(SELECT id FROM cache ORDER BY expires, rowid LIMIT 1)")
          end
        end
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
