# frozen_string_literal: true
require_relative "deepseek"

module Geo
  # Personal credentials and their scoped data live only in this process.
  class PersonalSessions
    TTL = 3600
    LIMIT = 32
    BUDGET = 5_000_000
    Entry = Struct.new(:config, :store, :expires, :ip, :revoked, :active)

    def initialize(clock: -> { Time.now.to_i })
      @clock, @mutex, @entries = clock, Mutex.new, {}
    end

    def prune
      @entries.delete_if do |_, entry|
        entry.revoked = true if entry.expires <= @clock.call
        next false unless entry.revoked && entry.active.zero?
        entry.store.close
        true
      end
    end

    def create(key, ip, replace: nil)
      @mutex.synchronize do
        prune
        old = @entries[Digest::SHA256.hexdigest(replace.to_s)]
        current = @entries.values.reject { |entry| entry.revoked || entry.equal?(old) }
        raise Error.new("connection_capacity", "个人连接较多，请稍后再试。", 503) if current.length >= LIMIT
        raise Error.new("connection_capacity", "当前网络的个人连接较多，请先断开已有连接。", 429) if current.count { |e| e.ip == ip } >= 4
        token = SecureRandom.hex(32)
        entry = Entry.new(Config.new(api_key: key, personal: true), Store.new(nil, memory: true, limit: BUDGET), @clock.call + TTL, ip, false, 0)
        @entries[Digest::SHA256.hexdigest(token)] = entry
        old.revoked = true if old
        prune
        [token, entry]
      end
    end

    def find(token)
      return nil unless token.to_s.match?(/\A[a-f0-9]{64}\z/)
      @mutex.synchronize do
        prune
        entry = @entries[Digest::SHA256.hexdigest(token)]
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
