# frozen_string_literal: true
require_relative "deepseek"

module Geo
  # Personal credentials and their scoped data live only in this process.
  class PersonalSessions
    TTL = 30 * 86_400
    LIMIT = 32
    BUDGET = 5_000_000
    Entry = Struct.new(:config, :store, :expires, :ip, :revoked, :active, :touched)

    def initialize(clock: -> { Time.now.to_i }, ledger: nil)
      @clock, @mutex, @entries = clock, Mutex.new, {}
      @ledger = ledger
    end

    def prune
      @entries.delete_if do |_, entry|
        entry.revoked = true if entry.expires <= @clock.call
        next false unless entry.revoked && entry.active.zero?
        entry.store.close
        true
      end
    end

    def create(key, ip, replace: nil, token: nil, expires: nil)
      @mutex.synchronize do
        prune
        if token && (existing = @entries[Digest::SHA256.hexdigest(token)])
          raise Error.new("busy", "原连接正在结束，请稍后重试。", 429) if existing.revoked
          return [token, existing]
        end
        old = @entries[Digest::SHA256.hexdigest(replace.to_s)]
        current = @entries.values.reject { |entry| entry.revoked || entry.equal?(old) }
        evicted = []
        while current.length >= LIMIT || current.count { |e| e.ip == ip } >= 4
          same_ip = current.count { |e| e.ip == ip } >= 4
          candidate = current.select { |e| e.active.zero? && (!same_ip || e.ip == ip) }.min_by(&:touched)
          raise Error.new("connection_capacity", "个人连接正在处理中，请稍后重试。", 429) unless candidate
          evicted << candidate
          current.delete(candidate)
        end
        token ||= SecureRandom.hex(32)
        expires ||= @clock.call + TTL
        usage = @ledger&.call(token, expires)
        entry = Entry.new(Config.new(api_key: key, personal: true), Store.new(nil, memory: true, limit: BUDGET, ledger: usage, expires_at: Time.at(expires)), expires, ip, false, 0, @clock.call)
        @entries[Digest::SHA256.hexdigest(token)] = entry
        old.revoked = true if old
        evicted.each { |e| e.revoked = true }
        prune
        [token, entry]
      end
    end

    def find(token)
      return nil unless token.to_s.match?(/\A[a-f0-9]{64}\z/)
      @mutex.synchronize do
        prune
        entry = @entries[Digest::SHA256.hexdigest(token)]
        entry.touched = @clock.call if entry
        entry unless entry&.revoked
      end
    end

    def use(token, exclusive: true)
      entry = @mutex.synchronize do
        prune
        value = @entries[Digest::SHA256.hexdigest(token.to_s)]
        raise Error.new("unauthorized", "个人连接已过期，请重新连接 DeepSeek Key。", 401) unless value && !value.revoked
        raise Error.new("busy", "当前连接已有搜索在处理，请稍候。", 429) if exclusive && value.active > 0
        value.active += 1
        value
      end
      yield entry
    ensure
      if entry
        @mutex.synchronize do
          entry.active -= 1
          prune
        end
      end
    end

    def delete(token)
      @mutex.synchronize do
        entry = @entries[Digest::SHA256.hexdigest(token.to_s)]
        entry.revoked = true if entry
        prune
      end
    end
  end
end
