# frozen_string_literal: true

require "webrick"
require_relative "pipeline"
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
    end

    def session(req)
      req.cookies.find { |cookie| cookie.name == COOKIE }.to_s.split("=", 2)[1].to_s
    end

    def json(res, data, status = 200)
      res.status = status
      res["Content-Type"] = "application/json; charset=utf-8"
      res.body = JSON.generate(data)
    end

    def authenticate!(req)
      token = session(req)
      raise Error.new("unauthorized", "请先输入内测访问口令。", 401) unless @store.session_valid?(token)
      token
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
      when ["GET", "/geo/api/status"]
        logged_in = @store.session_valid?(session(req))
        data = { "configured" => @config.configured?, "authenticated" => logged_in, "version" => Pipeline::VERSION }
        data["budget"] = @store.budget if logged_in
        json(res, data)
      when ["POST", "/geo/api/session"]
        @store.rate_limit("login:#{client_ip(req)}", 8, 300)
        password = input(req)["password"]
        raise Error.new("not_configured", "内测尚待配置，请先在电脑上运行密钥设置程序。", 503) unless @config.configured?
        raise Error.new("invalid_password", "内测口令不正确。", 401) unless password.is_a?(String) && @config.password_valid?(password)
        token = @store.session_create
        secure = ENV["APP_ENV"] == "production" ? "; Secure" : ""
        res["Set-Cookie"] = "#{COOKIE}=#{token}; Path=/geo/api/; Max-Age=43200; HttpOnly; SameSite=Strict#{secure}"
        json(res, { "authenticated" => true, "budget" => @store.budget })
      when ["DELETE", "/geo/api/session"]
        @store.session_delete(session(req))
        res["Set-Cookie"] = "#{COOKIE}=; Path=/geo/api/; Max-Age=0; HttpOnly; SameSite=Strict"
        json(res, { "authenticated" => false })
      when ["POST", "/geo/api/search"]
        token = authenticate!(req)
        payload = input(req)
        question = Pipeline.question(payload["question"])
        weights = Ranking.weights(payload["weights"])
        ranking_mode = Ranking.mode(payload["ranking_mode"])
        raise Error.new("not_configured", "请先完成 DeepSeek API Key 配置。", 503) unless @config.configured?
        @store.rate_limit("search:#{Digest::SHA256.hexdigest(token)}", 5, 60)
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
            pipeline = Pipeline.new(DeepSeek.new(@config, @store, transport: @transport), @store)
            result = pipeline.run(question, weights: weights, ranking_mode: ranking_mode, &emit)
            emit.call("result", result)
          rescue Error => error
            emit.call("error", { "code" => error.code, "message" => error.message, "budget" => @store.budget, "run_id" => pipeline && pipeline.run_id })
          rescue IOError, SystemCallError
            # Closing the browser ends the response and releases its concurrency slot.
          rescue StandardError => error
            warn "GEO pipeline error: #{error.class}"
            emit.call("error", { "code" => "internal_error", "message" => "本次处理未完成，请稍后再试。", "budget" => @store.budget })
          ensure
            @mutex.synchronize { @active -= 1 } if claimed
          end
        end
      else
        if req.request_method == "GET" && req.path.start_with?("/geo/api/runs/")
          authenticate!(req)
          id = req.path.delete_prefix("/geo/api/runs/")
          data = @config.redact_secrets(@store.diagnostics.read(id))
          res["Content-Disposition"] = "attachment; filename=geo-run-#{id}.json"
          json(res, data)
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
