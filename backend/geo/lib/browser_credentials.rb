# frozen_string_literal: true
require "base64"
require_relative "config"
require "securerandom"

module Geo
  class BrowserCredentials
    COOKIE = "geo_personal_key"
    TTL = 30 * 86_400
    AAD = "geo-browser-key-v1"

    def initialize(directory, clock: -> { Time.now.to_i })
      @clock = clock
      path = File.join(directory, "personal-browser.key")
      unless File.exist?(path)
        temporary = "#{path}.#{SecureRandom.hex(8)}.tmp"
        begin
          File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0600) { |f| f.write(SecureRandom.random_bytes(32)); f.flush; f.fsync }
          begin
            File.link(temporary, path)
          rescue Errno::EEXIST
            # Another process published its complete secret first.
          end
        ensure
          File.unlink(temporary) if File.exist?(temporary)
        end
      end
      File.open(path, File::RDONLY | File::NOFOLLOW) do |f|
        raise Error.new("unsafe_browser_secret", "浏览器保存功能的服务器配置需要检查。", 503) unless f.stat.file? && (f.stat.mode & 0077).zero? && f.stat.size == 32
        @secret = f.read
      end
    end

    def seal(key, token, expires)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = @secret
      iv = SecureRandom.random_bytes(12)
      cipher.iv = iv
      cipher.auth_data = AAD
      encrypted = cipher.update(JSON.generate("key" => key, "token" => token, "expires" => expires)) + cipher.final
      Base64.urlsafe_encode64(iv + cipher.auth_tag + encrypted, padding: false)
    end

    def open(value)
      return nil unless value.is_a?(String) && value.bytesize.between?(40, 2048) && value.match?(/\A[A-Za-z0-9_-]+\z/)
      bytes = Base64.urlsafe_decode64(value)
      return nil if bytes.bytesize <= 28
      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = @secret
      cipher.iv = bytes[0, 12]
      cipher.auth_tag = bytes[12, 16]
      cipher.auth_data = AAD
      data = JSON.parse(cipher.update(bytes[28..]) + cipher.final)
      return nil unless data.is_a?(Hash) && data["token"].is_a?(String) && data["token"].match?(/\A[a-f0-9]{64}\z/) &&
        data["key"].is_a?(String) && data["key"].match?(/\Ask-[A-Za-z0-9_-]{16,200}\z/) &&
        data["expires"].is_a?(Integer) && data["expires"] > @clock.call && data["expires"] <= @clock.call + TTL
      data
    rescue ArgumentError, JSON::ParserError, OpenSSL::Cipher::CipherError
      nil
    end
  end
end
