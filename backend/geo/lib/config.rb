# frozen_string_literal: true

require "json"
require "fileutils"
require "openssl"

module Geo
  class Error < StandardError
    attr_reader :code, :status
    def initialize(code, message, status = 422)
      super(message)
      @code, @status = code, status
    end
  end

  class Config
    BUDGET_MICROS = 50_000_000
    attr_reader :api_key, :password, :data_dir, :initial_spend

    def initialize(api_key: nil, password: nil, data_dir: nil, file: nil)
      file ||= ENV.fetch("GEO_CONFIG_FILE", File.expand_path("~/.config/laoyao-geo/credentials.json"))
      values = {}
      if File.file?(file)
        raise Error.new("unsafe_config", "请将密钥配置文件的权限设为 600。", 503) unless (File.stat(file).mode & 0077).zero?
        values = JSON.parse(File.read(file))
      end
      @api_key = api_key || ENV["DEEPSEEK_API_KEY"] || values["deepseek_api_key"].to_s
      @password = password || ENV["GEO_ACCESS_PASSWORD"] || values["access_password"].to_s
      @data_dir = data_dir || ENV.fetch("GEO_DATA_DIR", File.expand_path("~/.local/share/laoyao-geo"))
      @initial_spend = values.fetch("initial_spend_micros", 0)
      raise Error.new("invalid_config", "初始预算记录格式有误。", 503) unless @initial_spend.is_a?(Integer) && @initial_spend.between?(0, BUDGET_MICROS)
      FileUtils.mkdir_p(@data_dir, mode: 0700)
    rescue JSON::ParserError
      raise Error.new("invalid_config", "密钥配置格式有误，请重新运行设置程序。", 503)
    end

    def credentials_present?
      !@api_key.empty? && @password.length >= 12
    end

    def configured?
      credentials_present? && !File.exist?(File.join(@data_dir, "server-installed"))
    end

    def redact_secrets(value, redact_keys: true)
      secrets = [@api_key, @password].reject(&:empty?).flat_map do |secret|
        [secret, JSON.generate(secret)[1...-1], JSON.generate(secret, ascii_only: true)[1...-1]]
      end.uniq.sort_by { |secret| -secret.length }
      container_secrets = secrets.select { |secret| secret.lstrip.start_with?("{", "[") }
      redact = lambda do |item|
        case item
        when Hash then item.each_with_object({}) { |(key, content), result| result[redact_keys ? redact.call(key) : key] = redact.call(content) }
        when Array then item.map { |content| redact.call(content) }
        when String
          next "[REDACTED]" if secrets.include?(item)
          begin
            decoded = JSON.parse(item) if item.lstrip.start_with?("{", "[")
          rescue JSON::ParserError
            decoded = nil
          end
          if decoded.is_a?(Hash) || decoded.is_a?(Array)
            cleaned = redact.call(decoded)
            output = cleaned == decoded ? item : JSON.generate(cleaned)
            container_secrets.any? { |secret| output.include?(secret) } ? "[REDACTED]" : output
          else
            secrets.reduce(item) { |text, secret| text.gsub(secret, "[REDACTED]") }
          end
        else item
        end
      end
      redact.call(value)
    end

    def password_valid?(candidate)
      return false if @password.length < 12 || candidate.bytesize > 1024
      expected = OpenSSL::Digest::SHA256.digest(@password)
      actual = OpenSSL::Digest::SHA256.digest(candidate)
      expected.bytes.zip(actual.bytes).reduce(0) { |sum, (a, b)| sum | (a ^ b) }.zero?
    end
  end
end
