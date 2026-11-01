# frozen_string_literal: true

require "net/http"
require "uri"
require_relative "store"

module Geo
  class DeepSeek
    PRICE_DATE = "2026-11-01"
    def initialize(config, store, transport: nil)
      @config, @store, @transport = config, store, transport
      @deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 150
    end

    def post(path, payload, reservation, kind)
      raise Error.new("not_configured", "本机付费调用已关闭，请使用网站内测入口。", 503) unless @config.configured?
      remaining = @deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raise Error.new("deadline", "本次搜索已到时间上限，请缩小问题范围后再试。", 504) if remaining <= 0
      id = @store.reserve(kind, reservation)
      if @transport
        status, data = @transport.call(path, payload)
      else
        uri = URI("https://api.deepseek.com#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout, http.read_timeout, http.write_timeout = [10, remaining].min, [45, remaining].min, [15, remaining].min
        request = Net::HTTP::Post.new(uri.request_uri)
        request["Authorization"] = "Bearer #{@config.api_key}"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)
        response = http.request(request)
        status = response.code.to_i
        raise Error.new("response_too_large", "搜索服务返回内容较多，请缩小问题范围后重试。", 502) if response.body.bytesize > 5_000_000
        # A response whose body cannot be decoded keeps its reservation.
        data = JSON.parse(response.body)
      end
      if status != 200
        @store.settle(id, 0) if status.between?(400, 499)
        code, message = case status
                        when 401 then ["invalid_key", "DeepSeek 密钥无效，请重新配置。"]
                        when 402 then ["insufficient_balance", "DeepSeek 账户余额不足，请充值后再试。"]
                        when 403, 404 then ["page_unavailable", "该网页当前无法读取。"]
                        when 429 then ["upstream_busy", "DeepSeek 当前请求较多，请稍后再试。"]
                        else ["upstream_error", "DeepSeek 服务暂时未完成请求，请稍后再试。"]
                        end
        raise Error.new(code, message, 502)
      end
      amount = yield(data)
      @store.settle(id, amount) unless amount.nil?
      data
    rescue JSON::ParserError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      raise Error.new("upstream_connection", "上游连接中断，未确认的费用已保守预留，请稍后再试。", 502)
    end

    def search(query, question)
      post("/v1/tools/search", { "query" => query, "ori_question" => question[0, 128], "count" => 10, "need_content" => true }, 5000, "search") do |data|
        raise Error.new("invalid_search", "搜索返回的数据格式有误。", 502) unless data["results"].is_a?(Array)
        data["results"].empty? ? 0 : 5000
      end.fetch("results")
    end

    def fetch(url)
      post("/v1/tools/fetch", { "url" => url }, 5000, "fetch") do |data|
        data["content"].to_s.strip.empty? ? 0 : 5000
      end["content"].to_s
    end

    def json(system, input, max_tokens)
      payload = { "model" => "deepseek-flash", "thinking" => { "type" => "disabled" }, "stream" => false,
                  "response_format" => { "type" => "json_object" }, "max_tokens" => max_tokens,
                  "messages" => [{ "role" => "system", "content" => system }, { "role" => "user", "content" => input }] }
      # UTF-8 byte count plus protocol allowance bounds input token charges conservatively.
      reserve = (JSON.generate(payload).bytesize + 4096) * 2 + max_tokens * 8
      response = post("/chat/completions", payload, reserve, "model") do |data|
        usage = data["usage"]
        if usage.is_a?(Hash) && usage["prompt_tokens"].is_a?(Integer) && usage["completion_tokens"].is_a?(Integer) && usage["prompt_tokens"] >= 0 && usage["completion_tokens"] >= 0
          usage["prompt_tokens"] * 2 + usage["completion_tokens"] * 8
        end
      end
      choice = response.fetch("choices", [])[0]
      raise Error.new("incomplete_answer", "模型返回了未完成的结果，请稍后再试。", 502) unless choice && choice["finish_reason"] == "stop"
      value = JSON.parse(choice.fetch("message", {}).fetch("content", ""))
      raise Error.new("invalid_answer", "模型返回格式有误，请稍后再试。", 502) unless value.is_a?(Hash)
      value
    rescue JSON::ParserError
      raise Error.new("invalid_answer", "模型返回格式有误，请稍后再试。", 502)
    end
  end
end
