#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "../../backend/geo/lib/pipeline"

abort "真实接口检查会计入 50 元内测预算。运行方式：ruby ops/geo/check-live.rb --run" unless ARGV == ["--run"]
config = Geo::Config.new
abort "请先完成本机密钥设置。" unless config.configured?
store = Geo::Store.new(config.data_dir)
begin
  pipeline = Geo::Pipeline.new(Geo::DeepSeek.new(config, store), store)
  data = pipeline.run("DeepSeek Search 和 Fetch API 分别返回什么内容，按什么方式计费？") { |_, event| puts "步骤 #{event['stage'] + 1}：#{event['message']}" }
  data["answer"].each { |block| block["segs"].each { |segment| puts segment["x"] } }
  puts "引用来源："
  data["cited"].each { |id| puts data["sources"].find { |source| source["id"] == id }.fetch("url") }
  puts "预算记录：#{JSON.generate(store.budget)}"
  File.open(File.join(config.data_dir, "last-smoke.json"), "w", 0600) { |file| file.write(JSON.generate(data)) }
rescue Geo::Error => error
  warn "#{error.code}：#{error.message}"
  warn "预算记录：#{JSON.generate(store.budget)}"
  exit 1
ensure
  store.close
end
