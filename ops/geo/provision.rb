#!/usr/bin/env ruby
# frozen_string_literal: true
require "open3"
require "net/http"
require_relative "../../backend/geo/lib/store"
$stdout.sync = true
$stderr.sync = true

abort "安装到现有博客服务器：ruby ops/geo/provision.rb --install" unless ARGV == ["--install"]
root = File.expand_path("../..", __dir__)
config = Geo::Config.new
abort "请先完成本机密钥设置。" unless config.credentials_present?
store = Geo::Store.new(config.data_dir)
seed = store.retire_local!
store.close
head = Dir.chdir(root) { IO.popen(["git", "rev-parse", "HEAD"], &:read).strip }
payload = JSON.generate("deepseek_api_key" => config.api_key, "access_password" => config.password, "initial_spend_micros" => seed, "expected_commit" => head)
argv = ["ssh", "-i", File.expand_path("~/.ssh/id_ed25519_laoyao_blog_deploy"), "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=15", "root@39.107.137.177", "geo-configure"]
puts "通过现有专用连接安装 GEO 内测配置，密钥通过加密连接的标准输入传输。"
success = Open3.popen3(*argv) do |input, output, errors, waiter|
  input.write(payload)
  input.close
  streams = [Thread.new { output.each_line { |line| puts line } }, Thread.new { errors.each_line { |line| warn line } }]
  streams.each(&:join)
  waiter.value.success?
end
abort "服务器安装结果尚未确认。本机付费调用保持关闭，请检查网站状态后重试安装。" unless success
begin
  status = JSON.parse(Net::HTTP.get(URI("https://www.laoyao.cn/geo/api/status")))
  raise "status" unless status["configured"] && status["version"]
rescue StandardError
  abort "服务器配置状态尚未确认，本机付费调用保持关闭，请检查内测入口。"
end
puts "GEO 内测服务安装完成，本机验证费用已计入服务器初始预算。"
