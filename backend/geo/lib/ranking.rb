# frozen_string_literal: true
require "date"
require "set"

module Geo
  # The six teaching dimensions are measured locally from the returned search data.
  class Ranking
    DEFAULT = {"rel"=>30,"auth"=>20,"fresh"=>15,"struct"=>15,"gain"=>10,"cons"=>10}.freeze

    def self.weights(value)
      return DEFAULT.dup if value.nil?
      valid = value.is_a?(Hash) && value.keys.sort == DEFAULT.keys.sort &&
              value.values.all? { |v| v.is_a?(Integer) && v.between?(0, 50) } && value.values.sum > 0
      raise Error.new("invalid_weights", "请为六个维度设置 0～50 的权重，并至少保留一个非零值。", 400) unless valid
      DEFAULT.keys.each_with_object({}) { |key, result| result[key] = value[key] }
    end

    def self.score(source, weights)
      total, denominator = 0.0, 0
      DEFAULT.keys.each_with_index do |key, index|
        value = source["sig"][index]
        next unless value.is_a?(Numeric) && value.finite?
        total += value * weights[key]
        denominator += weights[key]
      end
      denominator.zero? ? nil : (total / denominator).round(6)
    end

    def self.tokens(text)
      (text.downcase.scan(/[a-z0-9]{2,}/) + text.scan(/(?=(\p{Han}{2}))/).flatten).uniq.take(600).to_set
    end

    def self.measure(sources, now:)
      docs = sources.map do |source|
        body = source["content"].to_s.strip
        text = body.empty? ? [source["summary"], source["snip"]].join("\n") : body
        {text: text, tokens: tokens(text), host: URI(source["url"]).host.downcase, basis: body.empty? ? "搜索摘要" : "搜索返回正文"}
      end
      sources.each_with_index do |source, index|
        doc = docs[index]
        peers = docs.select { |other| other[:host] != doc[:host] }
        terms = doc[:tokens]
        shared = terms.count { |term| peers.any? { |other| other[:tokens].include?(term) } }
        comparable = !peers.empty? && !terms.empty?
        lines = doc[:text].lines.map(&:strip).reject(&:empty?)
        prose = lines.count { |line| line.scan(/\p{Han}/).length >= 24 || line.scan(/[A-Za-z]/).length >= 100 || (line.length >= 12 && line.match?(/[。！？；.!?;]/)) }
        structure = doc[:text].scan(/(?:^\s*\#{1,6}\s|^\s*(?:\d+[.、]|[-*])\s|[：:])/).length
        struct = lines.empty? ? 0 : [100, prose.to_f / lines.length * 80 + [structure, 4].min * 5].min.round(2)
        age = begin
          day = Date.iso8601(source["date"].to_s[0, 10])
          distance = (now.getlocal("+08:00").to_date - day).to_i
          distance >= 0 ? distance : nil
        rescue ArgumentError
          nil
        end
        authority = source["authority"]
        known_auth = authority.is_a?(Integer) && authority.between?(0, 4)
        source["sig"] = [(source["api_score"] / 3.0 * 100).round(2), known_auth ? authority * 25.0 : nil,
                         age ? (100.0 / (1 + age / 365.0)).round(2) : nil, struct,
                         comparable ? ((terms.length - shared).to_f / terms.length * 100).round(2) : nil,
                         comparable ? (shared.to_f / terms.length * 100).round(2) : nil]
        source["sig_basis"] = [
          "API 综合排序分 #{format('%.2f', source['api_score'])}/3 映射至百分制，作为相关性代理；API 分数也含权威和时效因素。",
          known_auth ? "API 权威等级 #{authority}/4，乘以 25。" : "API 未提供已知权威等级，此项不参与该页面加权。",
          age ? "API 日期距今 #{age} 天；100 ÷ (1 + 天数 ÷ 365)。" : "API 日期未知或晚于当前日期，此项不参与该页面加权。",
          "#{doc[:basis]}中 #{prose}/#{lines.length} 行满足完整语句规则，另有 #{structure} 处标题、列表或定义标记。",
          comparable ? "#{terms.length} 个去重词项中 #{terms.length - shared} 个未在其他主机来源中出现，估计文本增量。" : "缺少其他主机来源或有效词项，暂无法估计文本增量。",
          comparable ? "#{terms.length} 个去重词项中 #{shared} 个在其他主机来源出现，估计跨站共现；具体事实需要继续核对。" : "缺少其他主机来源或有效词项，暂无法估计跨站共现。"
        ]
      end
    end

    def self.selectable?(source)
      source["eligible"] && source["language_allowed"] != false && !source["selection_blocked"] && !source["selection_deferred"]
    end

    def self.order(sources, weights)
      sources.each { |source| source["weighted_score"] = score(source, weights) }
      sources.sort_by { |source| [selectable?(source) && !source["weighted_score"].nil? ? 0 : 1, source["language_priority"] || 0, -(source["weighted_score"] || -1), -source["api_score"], source["url"]] }
    end
  end
end
