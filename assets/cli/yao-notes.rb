#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"
require "time"
require "fileutils"
require "optparse"
require "securerandom"
require "tempfile"

module YaoNotes
  VERSION = "1.0.0"
  DEFAULT_SOURCE = "https://www.laoyao.cn/"
  LEASE_SECONDS = 900

  class Error < StandardError
    attr_reader :code
    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  class Client
    def initialize(argv, out: $stdout, err: $stderr)
      @argv, @out, @err = argv.dup, out, err
      @source = URI(DEFAULT_SOURCE)
      @directory = nil
    end

    def run
      parser = OptionParser.new do |options|
        options.banner = "Usage: ruby yao-notes.rb [--source URL] [--state-dir DIR] COMMAND"
        options.separator "Commands: latest, init, check, ack BATCH_ID [ITEM_ID...], release BATCH_ID, status"
        options.on("--source URL", "Blog origin, including an optional base path") { |value| @source = safe_source(value) }
        options.on("--state-dir DIR", "Dedicated persistent subscription directory") { |value| @directory = File.expand_path(value) }
        options.on("--version") { @out.puts(VERSION); return 0 }
        options.on("--help", "-h") { @out.puts(options); return 0 }
      end
      parser.parse!(@argv)
      command = @argv.shift || "status"
      @directory ||= File.join(ENV.fetch("XDG_STATE_HOME", File.join(Dir.home, ".local", "state")), "yao-notes")
      @state_path = File.join(@directory, "state.json")
      result = case command
               when "latest"
                 arguments!(0)
                 manifest, items = read_feed
                 response("latest", nil, manifest).merge("items" => items.first(1))
               when "status"
                 arguments!(0)
                 state = read_state
                 response(state ? "ready" : "uninitialized", state)
               when "init", "check"
                 arguments!(0)
                 mutate { |state| discover(state, command) }
               when "ack", "release"
                 token = @argv.shift
                 fail!("invalid_arguments", "需要批次标识 BATCH_ID。") unless token
                 fail!("invalid_arguments", "release 只接受一个批次标识。") if command == "release" && !@argv.empty?
                 mutate(confirmation: true) { |state| confirm(state, command, token, @argv) }
               else
                 fail!("invalid_command", "未知命令，请运行 --help。")
               end
      @out.puts(JSON.generate(result))
      0
    rescue Error => error
      @err.puts(JSON.generate("error" => { "code" => error.code, "message" => error.message }))
      1
    rescue OptionParser::ParseError
      @err.puts(JSON.generate("error" => { "code" => "invalid_arguments", "message" => "命令参数无效，请运行 --help。" }))
      1
    rescue SystemCallError, IOError => error
      @err.puts(JSON.generate("error" => { "code" => "io_error", "message" => "无法读写订阅状态（#{error.class}）。" }))
      1
    end

    private

    def fail!(code, message)
      raise Error.new(code, message)
    end

    def arguments!(count)
      fail!("invalid_arguments", "存在多余参数，请运行 --help。") unless @argv.length == count
    end

    def safe_source(value)
      uri = URI.parse(value)
      loopback = %w[127.0.0.1 localhost ::1].include?(uri.hostname)
      unless uri.is_a?(URI::HTTP) && uri.host && uri.port.between?(1, 65_535) && (uri.scheme == "https" || loopback) && !uri.userinfo && !uri.query && !uri.fragment
        fail!("invalid_source", "来源须为 HTTPS 站点且端口有效；本机测试允许回环 HTTP。")
      end
      uri.path = uri.path.sub(%r{/*\z}, "") + "/"
      uri
    rescue URI::InvalidURIError
      fail!("invalid_source", "来源网址无效。")
    end

    def trusted_url(value)
      fail!("invalid_feed", "内容源缺少有效网址。") unless value.is_a?(String)
      uri = URI.parse(value)
      unless uri.is_a?(URI::HTTP) && uri.scheme == @source.scheme && uri.host == @source.host && uri.port == @source.port && !uri.userinfo && !uri.fragment && uri.path.start_with?(@source.path)
        fail!("untrusted_url", "内容源网址必须位于已选择的同一站点路径内。")
      end
      uri
    rescue URI::InvalidURIError
      fail!("invalid_feed", "内容源包含无效网址。")
    end

    def fetch_json(value, limit, redirects = 3)
      uri = trusted_url(value)
      body = +""
      redirect = nil
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 20
      http.start do |connection|
        request = Net::HTTP::Get.new(uri.request_uri, "Accept" => "application/json", "User-Agent" => "yao-notes/#{VERSION}")
        connection.request(request) do |response|
          response.read_body do |chunk|
            body << chunk
            fail!("response_too_large", "内容源超过允许大小。") if body.bytesize > limit
          end
          if response.is_a?(Net::HTTPRedirection)
            fail!("redirect_limit", "内容源重定向次数过多。") if redirects.zero?
            location = response["location"]
            fail!("invalid_redirect", "内容源重定向缺少有效网址。") unless location
            begin
              redirect = URI.join(uri.to_s, location).to_s
            rescue URI::InvalidURIError
              fail!("invalid_redirect", "内容源重定向网址无效。")
            end
          elsif !response.is_a?(Net::HTTPSuccess)
            fail!("http_error", "内容源返回 HTTP #{response.code}。")
          end
        end
      end
      return fetch_json(redirect, limit, redirects - 1) if redirect
      body.force_encoding(Encoding::UTF_8)
      fail!("invalid_json", "内容源未返回有效 UTF-8 JSON。") unless body.valid_encoding?
      JSON.parse(body)
    rescue JSON::ParserError, EncodingError
      fail!("invalid_json", "内容源未返回有效 JSON。")
    rescue Timeout::Error, SocketError, EOFError, Net::HTTPBadResponse, Net::ProtocolError, OpenSSL::SSL::SSLError, SystemCallError => error
      fail!("network_error", "无法读取内容源（#{error.class}）。")
    end

    def read_feed
      manifest = fetch_json(URI.join(@source.to_s, "subscribe/manifest.json").to_s, 131_072)
      unless manifest.is_a?(Hash) && manifest["schema_version"] == 1 && manifest["subscription_id"] == "yaojingang-weekly" && manifest["version"].is_a?(String) && manifest["version"].match?(/\A1\.\d+\.\d+\z/)
        fail!("unsupported_protocol", "订阅协议版本不兼容，请更新阅读 CLI。")
      end
      %w[feed_url archive_url instructions_url].each { |key| trusted_url(manifest[key]) }
      feed = fetch_json(manifest["feed_url"], 4_194_304)
      unless feed.is_a?(Hash) && feed["version"] == "https://jsonfeed.org/version/1.1" && feed["items"].is_a?(Array) && feed["items"].length <= 12
        fail!("invalid_feed", "内容源须为最近 12 期的 JSON Feed。")
      end
      items = feed["items"].map do |item|
        unless valid_item?(item)
          fail!("invalid_feed", "随笔缺少标识、网址、日期或完整正文。")
        end
        trusted_url(item["url"])
        begin
          date = Time.iso8601(item["date_published"])
        rescue ArgumentError
          fail!("invalid_feed", "随笔发布日期无效。")
        end
        fail!("future_item", "内容源包含尚未发布的随笔。") if date > Time.now
        item
      end
      fail!("duplicate_item", "内容源包含重复条目标识。") unless items.map { |item| item["id"] }.uniq.length == items.length
      [manifest, items.sort_by { |item| Time.iso8601(item["date_published"]) }.reverse]
    end

    def valid_item?(item)
      item.is_a?(Hash) && %w[id url title date_published content_html].all? { |key| item[key].is_a?(String) && !item[key].empty? } && item["id"].bytesize <= 4096
    end

    def no_symlink!(path)
      fail!("unsafe_state_path", "订阅状态路径不能是符号链接。") if File.symlink?(path)
    end

    def read_state
      no_symlink!(@directory)
      no_symlink!(@state_path)
      return nil unless File.exist?(@state_path)
      fail!("invalid_state", "状态文件大小异常，请保留文件并检查。") if File.size(@state_path) > 16_777_216
      serialized = File.binread(@state_path).force_encoding(Encoding::UTF_8)
      fail!("invalid_state", "状态文件编码无效，请保留原文件并检查。") unless serialized.valid_encoding?
      state = JSON.parse(serialized)
      valid = state.is_a?(Hash) && state["schema_version"] == 1 && state["source"].is_a?(String) &&
              %w[baseline acknowledged].all? { |key| state[key].is_a?(Array) && state[key].all? { |id| id.is_a?(String) } } &&
              state["pending"].is_a?(Hash) && state["pending"].all? { |id, item| valid_item?(item) && item["id"] == id } &&
              state["confirmations"].is_a?(Hash) &&
              state["archive_floor"].is_a?(String) && state["last_check_at"].is_a?(String)
      fail!("invalid_state", "状态文件结构无效，请保留文件并检查。") unless valid
      fail!("source_mismatch", "此状态目录属于另一来源，请选择独立目录。") unless state["source"] == @source.to_s
      Time.iso8601(state["archive_floor"])
      Time.iso8601(state["last_check_at"])
      state["pending"].each_value do |item|
        begin
          trusted_url(item["url"])
        rescue Error
          fail!("invalid_state", "待处理随笔网址无效，请保留原文件并检查。")
        end
        Time.iso8601(item["date_published"])
      end
      state["confirmations"].each do |token, receipt|
        unless token.is_a?(String) && receipt.is_a?(Hash) && receipt["acknowledged"].is_a?(Array) &&
               (receipt["acknowledged"] - state["acknowledged"]).empty? &&
               %w[completed released].all? { |key| receipt[key] == true || receipt[key] == false }
          fail!("invalid_state", "状态文件包含无效确认记录，请保留原文件并检查。")
        end
      end
      lease = state["lease"]
      if lease
        unless lease.is_a?(Hash) && lease["token"].is_a?(String) && lease["ids"].is_a?(Array) && (lease["ids"] - state["pending"].keys).empty? && lease["expires_at"].is_a?(String)
          fail!("invalid_state", "状态文件包含无效批次。")
        end
        Time.iso8601(lease["expires_at"])
      end
      state
    rescue JSON::ParserError, EncodingError
      fail!("invalid_state", "状态文件损坏，请保留原文件并检查。")
    rescue ArgumentError, TypeError
      fail!("invalid_state", "状态文件中的日期无效，请保留原文件并检查。")
    end

    def mutate(confirmation: false)
      no_symlink!(@directory)
      FileUtils.mkdir_p(@directory, mode: 0700)
      fail!("unsafe_state_path", "状态目录不能允许其他用户写入。") unless (File.stat(@directory).mode & 0022).zero?
      lock_path = File.join(@directory, "state.lock")
      no_symlink!(lock_path)
      File.open(lock_path, File::RDWR | File::CREAT, 0600) do |lock|
        unless lock.flock(File::LOCK_EX | File::LOCK_NB)
          fail!("state_busy", "状态正在使用，当前批次尚未确认，请保留批次标识并重试。") if confirmation
          return response("busy")
        end
        state, result = yield read_state
        serialized = JSON.pretty_generate(state) + "\n"
        fail!("state_too_large", "待处理状态超过允许大小，请先确认已有批次。") if serialized.bytesize > 16_777_216
        tempfile = Tempfile.new([".state-", ".json"], @directory)
        begin
          tempfile.chmod(0600)
          tempfile.write(serialized)
          tempfile.flush
          tempfile.fsync
          tempfile.close
          no_symlink!(@state_path)
          File.rename(tempfile.path, @state_path)
        ensure
          tempfile.close!
        end
        result
      end
    end

    def response(status, state = nil, manifest = nil)
      result = { "schema_version" => 1, "cli_version" => VERSION, "status" => status, "source" => @source.to_s, "items" => [] }
      if state
        result.merge!("state_file" => @state_path, "initialized" => true, "pending_count" => state["pending"].size,
                      "acknowledged_count" => state["acknowledged"].size, "baseline_count" => state["baseline"].size,
                      "history_gap" => !!state["history_gap"], "archive_floor" => state["archive_floor"])
      end
      result.merge!("protocol_version" => manifest["version"], "schedule" => manifest["schedule"], "archive_url" => manifest["archive_url"]) if manifest
      result
    end

    def discover(state, command)
      manifest, items = read_feed
      fresh = state.nil?
      now = Time.now.utc
      if fresh
        latest = items.first
        state = { "schema_version" => 1, "source" => @source.to_s, "initialized_at" => now.iso8601,
                  "baseline" => items.map { |item| item["id"] }, "acknowledged" => [], "pending" => {}, "confirmations" => {},
                  "archive_floor" => latest ? latest["date_published"] : now.iso8601,
                  "last_check_at" => now.iso8601, "history_gap" => false, "lease" => nil }
        state["pending"][latest["id"]] = latest if latest
      elsif command == "check"
        known = state["baseline"] + state["acknowledged"]
        oldest = items.last
        if oldest && (known & items.map { |item| item["id"] }).empty? && Time.iso8601(oldest["date_published"]) > Time.iso8601(state["last_check_at"])
          state["history_gap"] = true
        end
        items.each { |item| state["pending"][item["id"]] ||= item unless known.include?(item["id"]) }
      end
      state["protocol_version"] = manifest["version"]
      state["last_check_at"] = now.iso8601 if fresh || command == "check"
      lease = state["lease"]
      if lease && Time.iso8601(lease.fetch("expires_at")) > now
        return [state, response("busy", state, manifest)]
      end
      state["lease"] = nil
      pending = state["pending"].values.sort_by { |item| Time.iso8601(item["date_published"]) }
      return [state, response(fresh ? "initialized" : "idle", state, manifest)] if pending.empty?
      lease = { "token" => SecureRandom.hex(16), "ids" => pending.map { |item| item["id"] }, "expires_at" => (now + LEASE_SECONDS).iso8601 }
      state["lease"] = lease
      result = response(fresh ? "initialized" : "ready", state, manifest).merge("batch_id" => lease["token"], "lease_expires_at" => lease["expires_at"], "items" => pending)
      [state, result]
    rescue KeyError, ArgumentError, TypeError
      fail!("invalid_state", "订阅状态中的日期或批次无效，请保留原文件并检查。")
    end

    def confirm(state, command, token, ids)
      fail!("uninitialized", "请先运行 init。") unless state
      receipt = state["confirmations"][token]
      replay = receipt && if command == "release"
                            receipt["released"]
                          else
                            ids.empty? ? receipt["completed"] : (ids - receipt["acknowledged"]).empty?
                          end
      return [state, response(command == "ack" ? "acknowledged" : "released", state)] if replay
      lease = state["lease"]
      unless lease.is_a?(Hash) && lease["token"] == token && lease["ids"].is_a?(Array)
        fail!("invalid_batch", "批次标识无效或已被新批次替换，状态保持不变。")
      end
      receipt ||= { "acknowledged" => [], "completed" => false, "released" => false }
      if command == "release"
        receipt["released"] = true
        state["lease"] = nil
      else
        selected = ids.empty? ? lease["ids"] : ids.uniq
        unless (selected - lease["ids"] - receipt["acknowledged"]).empty?
          fail!("invalid_item", "只能确认当前批次中的条目。")
        end
        selected.each do |id|
          state["pending"].delete(id)
          state["acknowledged"] << id unless state["acknowledged"].include?(id)
        end
        receipt["acknowledged"] |= selected
        lease["ids"] -= selected
        receipt["completed"] = lease["ids"].empty?
        state["lease"] = nil if lease["ids"].empty?
        state["history_gap"] = false if state["pending"].empty?
      end
      state["confirmations"][token] = receipt
      [state, response(command == "ack" ? "acknowledged" : "released", state)]
    end
  end
end

exit YaoNotes::Client.new(ARGV).run if $PROGRAM_NAME == __FILE__
