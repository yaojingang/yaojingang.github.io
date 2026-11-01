#!/usr/bin/env ruby
# frozen_string_literal: true
require "tmpdir"
require "open3"
require "json"
require "rbconfig"

abort "请在隔离的 Ruby 容器中以 root 运行此离线检查。" unless Process.uid.zero?
Dir.mktmpdir("geo-provision-test-") do |directory|
  commit = "a" * 40
  input = File.join(directory, "input.json")
  nginx = File.join(directory, "nginx.conf")
  File.write(nginx, "server {\n  listen 80;\n}\n")
  payload = { "expected_commit" => commit, "deepseek_api_key" => "sk-offline-fixture-key", "access_password" => "offline-fixture-password", "initial_spend_micros" => 44_824 }
  script = File.join(__dir__, "provision-payload.rb")
  snippet = File.join(__dir__, "nginx-location.conf")
  run = lambda do |value|
    File.write(input, JSON.generate(value))
    output, errors, status = Open3.capture3(RbConfig.ruby, script, input, directory, nginx, snippet, commit)
    raise "Payload appeared in output" if (output + errors).include?(payload["deepseek_api_key"])
    status.success?
  end
  raise "Valid payload failed" unless run.call(payload)
  credentials = File.join(directory, "credentials.next.json")
  raise "Credential permissions" unless (File.stat(credentials).mode & 0777) == 0600 && File.stat(credentials).uid == 10001
  candidate = File.read(File.join(directory, "nginx.candidate.conf"))
  raise "Missing location" unless candidate.include?("location /geo/api/")
  File.write(nginx, candidate)
  raise "Repeat payload failed" unless run.call(payload)
  raise "Duplicate location" unless File.read(File.join(directory, "nginx.candidate.conf")).scan("location /geo/api/").length == 1
  raise "Wrong commit accepted" if run.call(payload.merge("expected_commit" => "b" * 40))
  raise "Oversized budget accepted" if run.call(payload.merge("initial_spend_micros" => 50_000_001))
  raise "Short password accepted" if run.call(payload.merge("access_password" => "short"))
  raise "Oversized payload accepted" if run.call(payload.merge("padding" => "x" * 17_000))
  puts "PASS: valid installation, private permissions, repeat configuration, and four rejection boundaries"
end
