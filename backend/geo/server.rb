#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "lib/app"

config = Geo::Config.new
store = Geo::Store.new(config.data_dir, initial_spend: config.initial_spend)
app = Geo::App.new(config, store)
server = WEBrick::HTTPServer.new(Port: ENV.fetch("PORT", "4010").to_i, BindAddress: ENV.fetch("BIND_HOST", "127.0.0.1"),
                               AccessLog: [], Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN), MaxClients: 16,
                               RequestTimeout: 180, ServerSoftware: "GEO")
server.mount("/", Geo::Servlet, app)
%w[INT TERM].each { |signal| trap(signal) { server.shutdown } }
puts "GEO 内测服务已启动。密钥状态：#{config.configured? ? '已配置' : '待配置'}；预算上限：50 元。"
begin
  server.start
ensure
  store.close
end
