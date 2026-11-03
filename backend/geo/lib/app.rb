# frozen_string_literal: true

require "webrick"
require_relative "pipeline"
require_relative "personal_sessions"
require_relative "browser_credentials"
require "ipaddr"

module Geo
  class Servlet < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, app)
      super(server)
      @app = app
    end

    def service(req, res)
      @app.call(req, res)
    end
  end

  class App
    COOKIE = "geo_session"
    ROOT = ENV.fetch("GEO_SITE_ROOT", File.expand_path("../../..", __dir__))

    def initialize(config, store, transport: nil, root: ROOT)
      @config, @store, @transport, @root = config, store, transport, root
      @mutex, @active = Mutex.new, 0
      ledger = ->(token, expires) { Store::PersonalLedger.new(@store, token, expires, PersonalSessions::BUDGET) }
      @personal, @key_checks = PersonalSessions.new(ledger: ledger), 0
      @browser_keys = BrowserCredentials.new(config.data_dir)
    end

    def session(req)
      req.cookies.find { |cookie| cookie.name == COOKIE }.to_s.split("=", 2)[1].to_s
    end

    def remembered(req)
      value = req.cookies.find { |cookie| cookie.name == BrowserCredentials::COOKIE }.to_s.split("=", 2)[1]
      data = @browser_keys.open(value)
      data unless data && @store.personal_revoked?(data["token"])
    end

    def authorized_personal(token)
      return nil unless token.to_s.match?(/\A[a-f0-9]{64}\z/)
      @personal.find(token) unless @store.personal_revoked?(token)
    end

    def restore_personal(req, res, explicit: false)
      data = remembered(req)
      return false unless data
      token = session(req)
      return false unless explicit || token == data["token"] || (token.empty? && req.path == "/geo/api/status")
      @personal.create(data["key"], client_ip(req), token: data["token"], expires: data["expires"]) unless @personal.find(data["token"])
      forget_session(token) if explicit && token != data["token"]
      set_cookie(res, data["token"], data["expires"] - Time.now.to_i) if explicit || token.empty?
      data["token"]
    end

    def clear_personal(req, res)
      data = remembered(req)
      token = data ? data["token"] : session(req)
      entry = @personal.find(token)
      if data || entry
        @store.revoke_personal(token, data ? data["expires"] : entry.expires)
        @personal.delete(token)
      end
      set_cookie(res, "", 0) if (data || entry) && session(req) == token
      set_cookie(res, "", 0, name: BrowserCredentials::COOKIE)
    end

    def json(res, data, status = 200)
      res.status = status
      res["Content-Type"] = "application/json; charset=utf-8"
      res.body = JSON.generate(data)
    end

    def authenticate!(req, token = session(req))
      raise Error.new("unauthorized", "请先连接自己的 DeepSeek Key，或输入团队内测口令。", 401) unless authorized_personal(token) || @store.session_valid?(token)
      token
    end

    def with_access(token, exclusive: false)
      if authorized_personal(token)
        @personal.use(token, exclusive: exclusive) { |entry| yield entry.config, entry.store, "personal", entry.expires }
      else
        raise Error.new("unauthorized", "连接已过期，请重新连接。", 401) unless @store.session_valid?(token)
        yield @config, @store, "team", nil
      end
    end

    def set_cookie(res, token, ttl, name: COOKIE)
      cookie = WEBrick::Cookie.new(name, token)
      cookie.path, cookie.max_age = "/geo/api/", ttl
      cookie.secure = true if ENV["APP_ENV"] == "production"
      # WEBrick preserves the HttpOnly and SameSite attributes in the extension.
      cookie.define_singleton_method(:to_s) { super() + "; HttpOnly; SameSite=Strict" }
      res.cookies.reject! { |old| old.name == name }
      res.cookies << cookie
    end

    def forget_session(token)
      @personal.delete(token)
      @store.session_delete(token)
    end

    def input(req)
      raise Error.new("invalid_content_type", "请使用 JSON 格式提交。", 415) unless req["content-type"].to_s.split(";").first == "application/json"
      body = req.body.to_s
      raise Error.new("request_too_large", "输入内容较长，请缩短问题。", 413) if body.bytesize > 4096
      value = JSON.parse(body)
      raise Error.new("invalid_request", "请求格式有误。", 400) unless value.is_a?(Hash)
      value
    rescue JSON::ParserError
      raise Error.new("invalid_request", "请求格式有误。", 400)
    end

    def call(req, res)
      res["Cache-Control"] = "no-store"
      res["X-Content-Type-Options"] = "nosniff"
      res["Referrer-Policy"] = "strict-origin-when-cross-origin"
      if req.request_method != "GET" && req["origin"]
        expected = ENV["APP_ENV"] == "production" ? "https://www.laoyao.cn" : "http://#{req['host']}"
        raise Error.new("invalid_origin", "请从 GEO 页面发起请求。", 403) unless req["origin"] == expected
      end
      case [req.request_method, req.path]
      when ["GET", "/geo/api/health"]
        json(res, { "ok" => true })
      when ["GET", "/geo/api/connect"]
        res["Content-Type"] = "text/html; charset=utf-8"
        res["Content-Security-Policy"] = "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
        res["Referrer-Policy"] = "no-referrer"
        res["X-Frame-Options"] = "DENY"
        res.body = File.read(File.expand_path("../views/connect.html", __dir__))
      when ["GET", "/geo/api/status"]
        token = restore_personal(req, res) || session(req)
        logged_in = !!authorized_personal(token) || @store.session_valid?(token)
        data = { "configured" => @config.configured?, "personal_available" => true, "authenticated" => logged_in, "version" => Pipeline::VERSION }
        saved = remembered(req)
        data["saved_key"] = !!saved
        data["saved_key_expires_at"] = saved["expires"] if saved
        if logged_in
          with_access(token) do |_, store, mode, expires|
            data.merge!("budget" => store.budget, "access_mode" => mode, "expires_at" => expires, "connection_id" => Digest::SHA256.hexdigest(token))
          end
        end
        json(res, data)
      when ["POST", "/geo/api/personal-session"]
        @store.rate_limit("key-connect-global", 60, 300)
        @store.rate_limit("key-connect:#{client_ip(req)}", 8, 300)
        key = input(req)["api_key"]
        checking = false
        begin
          @mutex.synchronize do
            raise Error.new("busy", "正在验证其他连接，请稍后重试。", 429) if @key_checks >= 2
            @key_checks += 1
            checking = true
          end
          DeepSeek.validate_key(key, transport: @transport)
          token, entry = @personal.create(key, client_ip(req), replace: session(req))
          previous = remembered(req)
          if previous
            @store.revoke_personal(previous["token"], previous["expires"])
            @personal.delete(previous["token"])
          end
          forget_session(session(req))
          set_cookie(res, token, PersonalSessions::TTL)
          set_cookie(res, @browser_keys.seal(key, token, entry.expires), PersonalSessions::TTL, name: BrowserCredentials::COOKIE)
          json(res, { "authenticated" => true, "access_mode" => "personal", "connection_id" => Digest::SHA256.hexdigest(token), "expires_at" => entry.expires, "budget" => entry.store.budget })
        ensure
          key = nil
          @mutex.synchronize { @key_checks -= 1 } if checking
        end
      when ["POST", "/geo/api/personal-session/restore"]
        token = restore_personal(req, res, explicit: true)
        raise Error.new("unauthorized", "浏览器没有可用的已保存 Key，请重新输入。", 401) unless token
        json(res, { "authenticated" => true, "access_mode" => "personal", "connection_id" => Digest::SHA256.hexdigest(token) })
      when ["DELETE", "/geo/api/personal-session"]
        clear_personal(req, res)
        json(res, { "saved_key" => false })
      when ["POST", "/geo/api/session"]
        @store.rate_limit("login:#{client_ip(req)}", 8, 300)
        password = input(req)["password"]
        raise Error.new("not_configured", "内测尚待配置，请先在电脑上运行密钥设置程序。", 503) unless @config.configured?
        raise Error.new("invalid_password", "内测口令不正确。", 401) unless password.is_a?(String) && @config.password_valid?(password)
        token = @store.session_create
        forget_session(session(req))
        set_cookie(res, token, 43_200)
        json(res, { "authenticated" => true, "access_mode" => "team", "connection_id" => Digest::SHA256.hexdigest(token), "budget" => @store.budget })
      when ["DELETE", "/geo/api/session"]
        clear_personal(req, res) if @personal.find(session(req)) || remembered(req)&.fetch("token") == session(req)
        forget_session(session(req))
        set_cookie(res, "", 0)
        json(res, { "authenticated" => false })
      when ["POST", "/geo/api/search"]
        token = authenticate!(req, restore_personal(req, res) || session(req))
        payload = input(req)
        question = Pipeline.question(payload["question"])
        weights = Ranking.weights(payload["weights"])
        ranking_mode = Ranking.mode(payload["ranking_mode"])
        connection_id = payload["connection_id"]
        if (authorized_personal(token) || connection_id) && connection_id != Digest::SHA256.hexdigest(token)
          raise Error.new("connection_changed", "浏览器连接已更换，请重新确认使用的 Key 或团队账户后再搜索。", 409)
        end
        @store.rate_limit("personal-search:#{client_ip(req)}", 5, 60) if authorized_personal(token)
        res["Content-Type"] = "text/event-stream; charset=utf-8"
        res["X-Accel-Buffering"] = "no"
        res.chunked = true
        res.body = proc do |out|
          claimed = false
          emit = ->(event, data) { out.write("event: #{event}\ndata: #{JSON.generate(data)}\n\n") }
          begin
            @mutex.synchronize do
              raise Error.new("busy", "已有两个问题正在处理中，请稍后再试。", 429) if @active >= 2
              @active += 1
              claimed = true
            end
            with_access(token, exclusive: true) do |config, store, mode, _|
              begin
                raise Error.new("not_configured", "请先完成 DeepSeek API Key 配置。", 503) unless config.configured?
                store.rate_limit("search:#{Digest::SHA256.hexdigest(token)}", 5, 60)
                authorize = if mode == "personal"
                              lambda do
                                raise Error.new("unauthorized", "保存的 Key 已清除或过期，后续调用已停止。", 401) unless authorized_personal(token)
                              end
                            end
                pipeline = Pipeline.new(DeepSeek.new(config, store, transport: @transport, authorize: authorize), store)
                result = pipeline.run(question, weights: weights, ranking_mode: ranking_mode, &emit)
                result["access_mode"] = mode
                emit.call("result", result)
              rescue Error => error
                emit.call("error", { "code" => error.code, "message" => error.message, "budget" => store.budget, "run_id" => pipeline && pipeline.run_id })
              end
            end
          rescue Error => error
            emit.call("error", { "code" => error.code, "message" => error.message })
          rescue IOError, SystemCallError
            # Closing the browser ends the response and releases its concurrency slot.
          rescue StandardError => error
            warn "GEO pipeline error: #{error.class}"
            emit.call("error", { "code" => "internal_error", "message" => "本次处理未完成，请稍后再试。" })
          ensure
            @mutex.synchronize { @active -= 1 } if claimed
          end
        end
      else
        if req.request_method == "GET" && req.path.start_with?("/geo/api/runs/")
          token = authenticate!(req, restore_personal(req, res) || session(req))
          id = req.path.delete_prefix("/geo/api/runs/")
          with_access(token) do |config, store, _, _|
            data = config.redact_secrets(store.diagnostics.read(id))
            res["Content-Disposition"] = "attachment; filename=geo-run-#{id}.json"
            json(res, data)
          end
        else
          serve_static(req, res)
        end
      end
    rescue Error => error
      json(res, { "error" => { "code" => error.code, "message" => error.message } }, error.status)
    rescue URI::InvalidURIError
      json(res, { "error" => { "code" => "invalid_origin", "message" => "请求来源格式有误。" } }, 403)
    rescue StandardError => error
      warn "GEO request error: #{error.class}"
      json(res, { "error" => { "code" => "internal_error", "message" => "请求暂未完成，请稍后再试。" } }, 500)
    end

    def client_ip(req)
      peer = req.peeraddr[3]
      address = IPAddr.new(peer)
      trusted_proxy = address.loopback? || IPAddr.new("172.16.0.0/12").include?(address)
      if ENV["APP_ENV"] == "production" && trusted_proxy && req["x-real-ip"]
        return IPAddr.new(req["x-real-ip"]).to_s
      end
      peer
    rescue IPAddr::InvalidAddressError
      peer
    end

    def serve_static(req, res)
      files = { "/geo/" => ["geo/index.html", "text/html"], "/geo/index.html" => ["geo/index.html", "text/html"],
                "/geo/live.js" => ["geo/live.js", "text/javascript"], "/geo/live.css" => ["geo/live.css", "text/css"],
                "/geo/connect.js" => ["geo/connect.js", "text/javascript"], "/geo/connect.css" => ["geo/connect.css", "text/css"],
                "/geo/test-questions.json" => ["geo/test-questions.json", "application/json"] }
      if req.request_method == "GET" && %w[/ /geo].include?(req.path)
        res.status, res["Location"], res.body = 302, "/geo/", ""
      elsif req.request_method == "GET" && files.key?(req.path) && File.file?(File.join(@root, files[req.path][0]))
        path, type = files[req.path]
        body = File.read(File.join(@root, path))
        if type == "text/html"
          body = body.sub(/\A---\n.*?\n---\n/m, "").gsub("{% include baidu-analytics.html %}", "")
        end
        res["Content-Type"] = "#{type}; charset=utf-8"
        res.body = body
      else
        json(res, { "error" => { "code" => "not_found", "message" => "没有找到该接口。" } }, 404)
      end
    end
  end
end
