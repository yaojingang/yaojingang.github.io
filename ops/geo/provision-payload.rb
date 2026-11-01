# frozen_string_literal: true
require "json"
require "fileutils"

begin
  input, directory, nginx, snippet, commit = ARGV
  raise "size" if File.size(input) > 16_384
  data = JSON.parse(File.read(input))
  raise "commit" unless data["expected_commit"] == commit && commit.match?(/\A[a-f0-9]{40}\z/)
  key, password, seed = data.values_at("deepseek_api_key", "access_password", "initial_spend_micros")
  raise "key" unless key.is_a?(String) && key.start_with?("sk-") && key.length.between?(16, 512) && !key.match?(/\s/)
  raise "password" unless password.is_a?(String) && password.length.between?(12, 256)
  raise "budget" unless seed.is_a?(Integer) && seed.between?(0, 50_000_000)
  original = File.read(nginx)
  raise "nginx" unless original.scan(/^\s*server\s*\{/).length == 1 && original.match?(/\}\s*\z/)
  marker = "# BEGIN LAOYAO GEO API"
  block = /^\s*# BEGIN LAOYAO GEO API\n.*?^\s*# END LAOYAO GEO API(?:\n|\z)/m
  if original.include?(marker)
    raise "markers" unless original.scan(block).length == 1
    candidate = original.sub(block, File.read(snippet))
  else
    candidate = original.sub(/\}\s*\z/, "#{File.read(snippet)}\n}\n")
  end
  File.open(File.join(directory, "nginx.candidate.conf"), "w", 0600) { |file| file.write(candidate) }
  credentials = File.join(directory, "credentials.next.json")
  File.open(credentials, "w", 0600) { |file| file.write(JSON.generate("deepseek_api_key" => key, "access_password" => password, "initial_spend_micros" => seed)) }
  File.chown(10001, 10001, credentials)
  puts "GEO 配置校验通过。"
rescue StandardError
  warn "GEO 配置校验未通过，请检查提交版本、密钥格式、口令长度及现有 Nginx 文件结构。"
  exit 1
end
