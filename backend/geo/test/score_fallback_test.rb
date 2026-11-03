# frozen_string_literal: true
require_relative "core_test"

class GeoScoreFallbackTest < Minitest::Test
  include GeoFixtures
  BODY = "企业数据分析工具的选择，需要比较数据规模、团队协作需求和长期接入成本。"

  def row(name, score, **fields)
    { "url" => "https://#{name}.example.org/guide", "title" => "企业分析工具选型", "site_name" => name,
      "content" => BODY, "rerank_score" => score, "authority" => 3 }.merge(fields.transform_keys(&:to_s))
  end

  def run_rows(rows, question: "企业分析工具", **options)
    base = transport
    provider = lambda do |path, payload|
      response = base.call(path, payload)
      path == "/v1/tools/search" ? [200, { "results" => rows }] : response
    end
    Geo::Pipeline.new(Geo::DeepSeek.new(@config, @store, transport: provider), @store).run(question, **options) { |*_| }
  end

  def reasons(data)
    data.fetch("quality").fetch("insufficiency_reasons").map { |item| item.fetch("code") }
  end

  def test_relevant_fallback_at_one_point_generates_an_answer_and_preserves_scores
    data = run_rows([row("floor", 1.0), row("fallback", 1.49), row("below", 0.999)])
    assert_equal "complete", data["status"]
    assert_equal [1.49, 1.0], data["sources"].select { |s| s["read"] }.map { |s| s["api_score"] }
    assert_equal 1.0, data["quality"]["min_score"]
    assert_equal 1.5, data["quality"]["preferred_score"]
    assert_equal 2, data["quality"]["fallback_read_count"]
    assert data["quality"]["fallback_used"]
    assert_empty reasons(data)
    assert_equal [0, 1, 2, 3, 4, 5], data["trace"].map { |s| s["stage"] }.uniq
    assert_equal 2, @calls.count { |path, _| path == "/chat/completions" }
    refute data["sources"].find { |s| s["site"] == "below" }["read"]
    calls = @calls.length
    cached = run_rows([row("floor", 1.0), row("fallback", 1.49), row("below", 0.999)])
    assert cached["cached"]
    assert_equal calls, @calls.length
    assert_equal data["evidence"], cached["evidence"]
    assert_equal data["quality"], cached["quality"]
    assert data["sources"].select { |s| s["read"] }.all? { |s| s["score_tier"] == "fallback" && s["why"].include?("补充") }
    answer_request = @calls.select { |path, _| path == "/chat/completions" }.last[1]
    assert JSON.parse(answer_request["messages"][1]["content"])["sources"].all? { |s| s["score_tier"] == "fallback" && s["api_score"] >= 1.0 }
  end

  def test_preferred_sources_fill_all_five_slots_before_fallback_even_in_teaching_mode
    rows = 5.times.map { |i| row("high#{i}", 1.5 + i * 0.1, authority: 1) } + [row("low", 1.49, authority: 4)]
    weights = Geo::Ranking::DEFAULT.transform_values { 0 }.merge("auth" => 50)
    data = run_rows(rows, weights: weights, ranking_mode: "teaching")
    assert_equal 5, data["quality"]["read_count"]
    assert_equal 0, data["quality"]["fallback_read_count"]
    refute data["quality"]["fallback_used"]
    refute data["sources"].find { |s| s["site"] == "low" }["attempted"]
    assert data["sources"].first(5).all? { |s| s["score_tier"] == "preferred" }
  end

  def test_unusable_preferred_content_allows_relevant_fallback
    data = run_rows([row("navigation", 2.5, content: "首页\n登录"), row("low", 1.3)])
    assert_equal "complete", data["status"]
    assert_equal ["low"], data["sources"].select { |s| s["read"] }.map { |s| s["site"] }
    assert_equal 1, data["quality"]["fallback_read_count"]
    assert data["trace"].any? { |s| s["stage"] == 3 && s["message"].include?("补充") }
  end

  def test_fallback_drops_unrelated_prose_and_records_topic_mismatch
    data = run_rows([row("unrelated", 1.3, content: "在晴朗的天气里，植物通过光合作用吸收二氧化碳并释放氧气。")])
    assert_equal "insufficient", data["status"]
    assert_empty data["evidence"]
    assert_includes reasons(data), "fallback_topic_mismatch"
    assert_equal 1, @calls.count { |path, _| path == "/chat/completions" }
    assert_match(/主题词/, data["sources"][0]["why"])
  end

  def test_fallback_checks_relevant_summary_after_unrelated_body
    data = run_rows([row("summary", 1.2, content: "植物在晴朗的天气里进行光合作用，为生长积累能量。", summary: BODY)])
    assert_equal "complete", data["status"]
    assert_equal "搜索摘要", data["sources"][0]["type"]
    assert_equal [BODY], data["evidence"].map { |e| e["text"] }
  end

  def test_cross_language_query_terms_can_admit_an_english_fallback
    question = "企业分析工具"
    base = transport
    provider = lambda do |path, payload|
      response = base.call(path, payload)
      if path == "/chat/completions" && payload["max_tokens"] == 600
        response[1]["choices"][0]["message"]["content"] = JSON.generate("queries" => [question, "analytics platforms"])
      elsif path == "/v1/tools/search"
        response = [200, { "results" => payload["query"] == question ? [] : [row("english", 1.2, content: "Analytics platforms help enterprise teams compare integration costs and data collaboration needs.")] }]
      end
      response
    end
    data = Geo::Pipeline.new(Geo::DeepSeek.new(@config, @store, transport: provider), @store).run(question) { |*_| }
    assert_equal "complete", data["status"]
    assert_equal "en", data["sources"][0]["language"]
    refute data["quality"]["strict_language"]
    refute data["searches"].any? { |s| s["query"].include?("lang:") }
  end

  def test_insufficient_states_explain_empty_search_invalid_links_and_low_scores
    [
      [[], "no_results"],
      [[row("invalid", 2.0, url: "javascript:alert(1)")], "invalid_links"],
      [[row("low", 0.99)], "score_below_floor"],
      [[row("nav", 2.0, content: "首页\n登录")], "missing_content"]
    ].each_with_index do |(rows, code), index|
      data = run_rows(rows, question: "企业分析工具 #{index}")
      assert_equal "insufficient", data["status"]
      assert_includes reasons(data), code
      assert data["diagnostic"].include?(data["quality"]["insufficiency_reasons"][0]["message"])
      assert data["quality"]["insufficiency_reasons"].all? { |r| r["action"].is_a?(String) && !r["action"].empty? }
    end
  end

  def test_fallback_never_overrides_explicit_language_restrictions
    data = run_rows([row("chinese", 1.3)], question: "只用英文资料，企业分析工具怎么选择？")
    assert_equal "insufficient", data["status"]
    assert_includes reasons(data), "language_restricted"
    assert_empty data["evidence"]
  end

  def test_fetch_limit_is_reported_and_lower_scores_cannot_trigger_more_fetches
    rows = 7.times.map { |i| row("empty#{i}", 1.49 - i * 0.01, content: "") }
    base = transport
    provider = lambda do |path, payload|
      response = base.call(path, payload)
      path == "/v1/tools/search" ? [200, { "results" => rows }] : path == "/v1/tools/fetch" ? [404, { "error" => {} }] : response
    end
    data = Geo::Pipeline.new(Geo::DeepSeek.new(@config, @store, transport: provider), @store).run("企业分析工具") { |*_| }
    assert_equal "insufficient", data["status"]
    assert_equal 5, data["processing"]["fetch_attempts"]
    assert_includes reasons(data), "fetch_limit"
    assert_includes reasons(data), "missing_content"
    assert_equal 5, data["quality"]["insufficiency_reasons"].find { |r| r["code"] == "missing_content" }["count"]
    assert_equal 2, data["quality"]["insufficiency_reasons"].find { |r| r["code"] == "fetch_limit" }["count"]
    assert_empty data["evidence"]
  end

  def test_headers_links_urls_and_word_fragments_do_not_pass_fallback_topic_check
    unrelated = "植物在晴朗的天气里通过光合作用吸收二氧化碳，并为生长积累能量。"
    ["# 企业分析工具\n#{unrelated}", "企业分析工具\n==========\n#{unrelated}", "企业分析工具\n---\n#{unrelated}", "#{unrelated} [企业分析工具](https://external.example.org/企业分析工具)",
     "#{unrelated} https://external.example.org/企业分析工具",
     "#{unrelated} [查看](https://external.example.org/(topic)企业分析工具)", "#{unrelated} [企业分析工具][ref]"].each_with_index do |content, index|
      data = run_rows([row("unrelated#{index}", 1.2, content: content)], question: "企业分析工具 #{index}")
      assert_equal "insufficient", data["status"]
      assert_includes reasons(data), "fallback_topic_mismatch"
    end
    data = run_rows([row("fragment", 1.2, content: "Wooden chairs are placed around a dining table to provide comfortable seating for family meals.")], question: "What is an AI agent?")
    assert_equal "insufficient", data["status"]
    assert_empty data["evidence"]
    positive = run_rows([row("agent", 1.2, content: "An AI agent uses tools and observations to plan actions toward the goal requested by its user.")], question: "What is an AI agent? positive")
    assert_equal "complete", positive["status"]
    refute_empty positive["evidence"]
  end

  def test_topic_mismatch_reason_uses_all_content_before_display_truncation
    body = (["首页\n登录"] * 15 + ["植物在晴朗的天气里进行光合作用，吸收二氧化碳并释放氧气。"] ).join("\n\n")
    data = run_rows([row("long", 1.3, content: body)])
    assert_equal "insufficient", data["status"]
    assert_includes reasons(data), "fallback_topic_mismatch"
  end

  def test_missing_teaching_dimensions_are_explained
    weights = Geo::Ranking::DEFAULT.transform_values { 0 }.merge("auth" => 50)
    data = run_rows([row("unknown", 2.5, authority: -1)], ranking_mode: "teaching", weights: weights)
    assert_equal "insufficient", data["status"]
    assert_includes reasons(data), "missing_rank_data"
    assert_match(/DeepSeek/, data["quality"]["insufficiency_reasons"].first["action"])
  end
end
