# frozen_string_literal: true
require_relative "core_test"

class GeoLanguageTest < Minitest::Test
  include GeoFixtures
  SIMPLE = "根据数据规模和团队协作需求，选择适合企业的数据分析工具。"
  TRADITIONAL = "根據資料規模與團隊協作需求，選擇適合企業的資料分析工具。"
  ENGLISH = "The official guide explains how to choose data analysis tools for your team and compare the cost of collaboration."

  def result(name, content, score = 2.5, **extra)
    { "url" => "https://#{name}.example.org/guide", "title" => name, "content" => content,
      "summary" => "", "snippet" => "", "rerank_score" => score, "authority" => 3 }.merge(extra.transform_keys(&:to_s))
  end

  def run_with(question, rows:, fetch: nil, weights: nil)
    base = transport
    client = Geo::DeepSeek.new(@config, @store, transport: lambda do |path, payload|
      response = base.call(path, payload)
      if path == "/v1/tools/search"
        [200, { "results" => rows }]
      elsif path == "/v1/tools/fetch" && fetch
        [200, { "content" => fetch }]
      else
        response
      end
    end)
    Geo::Pipeline.new(client, @store).run(question, weights: weights, ranking_mode: weights ? "teaching" : "api") { |*_| }
  end

  def test_detects_question_language_without_creating_a_default_source_lock
    { "How does Google Search discover and index pages?" => "en", "数据分析工具推荐" => "zh-Hans",
      "資料分析工具推薦" => "zh-Hant", "DeepSeek API 怎么用？" => "zh-Hans", "DeepSeek API 如何使用？" => "zh-Hans",
      "Compare 腾讯云 and 阿里云 for our team" => "en", "你好" => "zh-Hans" }.each do |question, expected|
      policy = Geo::Language.preference(question)
      assert_equal expected, policy["preferred"], question
      assert_empty policy["codes"], question
      refute policy["strict"], question
      assert_nil Geo::DeepSeek.search_language(question)
    end
    assert_equal "zh", Geo::Language.detect("人工智能方法")
    assert_equal "ja", Geo::Language.detect("これは日本語の資料です。")
    assert_equal "other", Geo::Language.detect("Recherche et informations sur les études mathématiques.")
    assert_equal "unknown", Geo::Language.detect("123 / ++")
  end

  def test_default_queries_have_no_language_operator_and_planner_operators_cannot_add_one
    assert_equal "Google Search", Geo::DeepSeek.search_query("Google Search", "How does Google Search work?")
    assert_equal "Google 搜索", Geo::DeepSeek.search_query("Google 搜索 lang:zh", "搜索")
    assert_equal "Google 搜索 lang:en", Geo::DeepSeek.search_query("Google 搜索 lang:zh", "只用英文资料，Google 搜索")
  end

  def test_native_rank_and_evidence_are_shared_across_languages_for_all_question_scripts
    rows = [result("simple", SIMPLE, 1.6), result("traditional", TRADITIONAL, 2.9), result("english", ENGLISH, 3)]
    ["数据分析工具怎么选择？", "資料分析工具應該怎麼選擇？", "How should our team choose data analysis tools?"].each do |question|
      data = run_with(question, rows: rows)
      assert_equal [3.0, 2.9, 1.6], data["sources"].map { |source| source["api_score"] }
      assert_equal [ENGLISH, TRADITIONAL, SIMPLE], data["evidence"].map { |item| item["text"] }
      assert data["sources"].all? { |source| source["read"] && source["language_allowed"] }
      assert data["searches"].all? { |search| !search["query"].include?("lang:") }
      assert_equal 2, data["searches"].length
      refute data["quality"]["supplement_searched"]
      refute data["quality"]["language_fallback"]
      input = JSON.parse(@calls.reverse.find { |path, payload| path == "/chat/completions" && payload["max_tokens"] == 3000 }[1]["messages"][1]["content"])
      assert_equal Geo::Language.detect(question, question: true), input["response_language"]
      assert_equal input["response_language"], data["quality"]["response_language"]
    end
  end

  def test_higher_scored_foreign_sources_fill_all_five_slots_without_a_language_bonus
    rows = [result("simple", SIMPLE, 1.6)] + 5.times.map { |i| result("foreign#{i}", ENGLISH, 3 - i * 0.1) }
    data = run_with("数据分析工具怎么选择？", rows: rows)
    assert_equal 5, data["quality"]["read_count"]
    assert data["sources"].select { |source| source["read"] }.all? { |source| source["language"] == "en" }
    refute data["sources"].find { |source| source["language"] == "zh-Hans" }["read"]
    assert data["sources"].all? { |source| source["language_allowed"] }
    assert_empty data["warnings"]
  end

  def test_fetch_can_reveal_foreign_content_without_another_language_search
    data = run_with("数据分析工具怎么选择？", rows: [result("masked", "", 2.8, title: "数据分析工具推荐")], fetch: ENGLISH)
    assert_equal "complete", data["status"]
    assert_equal [ENGLISH], data["evidence"].map { |item| item["text"] }
    assert_equal 1, @calls.count { |path, _| path == "/v1/tools/fetch" }
    assert_equal 2, data["searches"].length
    assert_equal "en", data["sources"].first["language"]
  end

  def test_only_one_language_of_results_does_not_trigger_supplemental_searches
    data = run_with("数据分析工具怎么选择？", rows: [result("english", ENGLISH)])
    assert_equal "complete", data["status"]
    assert_equal 2, data["searches"].length
    assert_equal [ENGLISH], data["evidence"].map { |item| item["text"] }
    refute data["quality"]["supplement_searched"]
    assert_empty data["warnings"]
  end

  def test_strict_language_requests_never_broaden
    ["只用简体中文资料，数据分析工具怎么选择？", "数据分析工具推荐 lang:zh"].each do |question|
      rows = question.include?("lang:zh") ? [result("english", ENGLISH)] : [result("traditional", TRADITIONAL)]
      data = run_with(question, rows: rows)
      assert_equal "insufficient", data["status"]
      assert data["quality"]["strict_language"]
      assert data["searches"].all? { |search| search["query"].end_with?(" lang:zh") }
      assert_equal 2, data["searches"].length
      assert_empty data["evidence"]
      assert data["sources"].all? { |source| !source["language_allowed"] }
      assert_equal 1, @calls.count { |path, payload| path == "/chat/completions" && payload["max_tokens"] == 600 && payload["messages"][1]["content"].include?(question) }
    end
  end

  def test_strict_limits_are_rechecked_after_fetch
    data = run_with("只用简体中文资料，数据分析工具怎么选择？", rows: [result("masked", "", 2.8, title: "数据分析工具推荐")], fetch: ENGLISH)
    assert_equal "insufficient", data["status"]
    assert_empty data["evidence"]
    refute data["sources"].first["language_allowed"]
    assert_equal 1, @calls.count { |path, _| path == "/v1/tools/fetch" }
  end

  def test_natural_language_limits_preserve_answer_language_separately
    data = run_with("Use only Chinese sources for data analysis tools.", rows: [result("simple", SIMPLE, 1.6), result("english", ENGLISH, 3)])
    assert data["quality"]["strict_language"]
    assert_equal [SIMPLE], data["evidence"].map { |item| item["text"] }
    assert_equal "en", data["quality"]["response_language"]
    assert_equal "zh", Geo::DeepSeek.search_language("Use only Chinese sources for data analysis tools.")
    assert_equal "en", Geo::DeepSeek.search_language("只使用英文的资料，数据分析工具怎么选择？")
  end

  def test_excluded_languages_remain_blocked_with_unrestricted_search
    ["不要引用英文资料，请推荐数据分析工具", "英文资料不要用，请推荐数据分析工具"].each do |question|
      data = run_with(question, rows: [result("english", ENGLISH, 3), result("traditional", TRADITIONAL, 2.8), result("simple", SIMPLE, 1.6)])
      assert_equal [TRADITIONAL, SIMPLE], data["evidence"].map { |item| item["text"] }
      refute data["sources"].find { |source| source["language"] == "en" }["language_allowed"]
      assert data["searches"].all? { |search| !search["query"].include?("lang:") }
    end
  end

  def test_no_usable_results_stop_without_paid_language_fallback
    data = run_with("数据分析工具怎么选择？", rows: [result("navigation", "首页\n联系我们")])
    assert_equal "insufficient", data["status"]
    assert_equal 2, data["searches"].length
    assert_equal 1, @calls.count { |path, _| path == "/chat/completions" }
    assert_empty data["evidence"]
  end

  def test_quality_threshold_and_fetch_limit_still_apply_across_languages
    rows = 5.times.map { |i| result("empty#{i}", "", 3, title: "工具资料") } + [result("english", ENGLISH, 2.5), result("low", SIMPLE, 0.99)]
    data = run_with("数据分析工具怎么选择？", rows: rows, fetch: "首页\n联系我们")
    assert_equal 5, data["processing"]["fetch_attempts"]
    assert_equal [ENGLISH], data["evidence"].map { |item| item["text"] }
    refute data["sources"].find { |source| source["api_score"] == 0.99 }["read"]
    assert_equal 2, data["searches"].length
  end

  def test_teaching_mode_uses_weights_across_languages_and_keeps_exclusions
    weights = Geo::Ranking::DEFAULT.transform_values { 0 }.merge("auth" => 50)
    data = run_with("数据分析工具怎么选择？", rows: [result("simple", SIMPLE, 3, authority: 1), result("english", ENGLISH, 1.6, authority: 4)], weights: weights)
    assert_equal "en", data["sources"].first["language"]
    assert_equal [ENGLISH, SIMPLE], data["evidence"].map { |item| item["text"] }
    limited = run_with("不要英文资料，数据分析工具怎么选择？", rows: [result("simple", SIMPLE, 3, authority: -1), result("english", ENGLISH, 1.6, authority: 4)], weights: weights)
    assert_equal "insufficient", limited["status"]
    assert_empty limited["evidence"]
  end

  def test_shared_traditional_characters_do_not_cancel_distinct_traditional_signals
    ["台灣教育", "台灣生活", "台灣美食", "台灣AI", "發布資料", "雲端服務的使用規范", "搜尋引擎", "我們", "什麼是AI", "兩個方案", "區塊鏈"].each do |question|
      assert_equal "zh-Hant", Geo::Language.preference(question)["preferred"], question
    end
  end

  def test_explicit_source_directives_are_distinct_from_language_discussion_or_preference
    { "只查英文资料，解释数据工具" => "en", "Use only English sources for this answer." => "en", "Please use only English sources." => "en", "请只使用简体中文资料，解释工具接入" => "zh" }.each do |question, language|
      assert_equal language, Geo::DeepSeek.search_language(question)
    end
    ["请查英文资料，解释数据工具", "Use English sources for this answer.", "Please use English sources.", "请使用简体中文资料，解释工具接入", "优先使用英文资料，解释工具接入", "Prefer to use English sources", "How do AI tools use English sources?", "中文资料和英文资料有什么差别？"].each do |question|
      assert_nil Geo::DeepSeek.search_language(question), question
    end
  end

  def test_language_discussion_and_alternatives_do_not_lock_sources
    ["使用英文资料有什么优缺点？", "查找英文资料的方法有哪些？", "Use English sources or Chinese sources, whichever is most relevant.", "使用英文资料回答问题有什么好处？", "查找英文资料来学习数据分析的方法有哪些？", "请查英文资料，中文也可以。"].each do |question|
      data = run_with(question, rows: [result("simple", SIMPLE, 3)])
      refute data["quality"]["strict_language"], question
      assert_equal "complete", data["status"], question
      assert_equal [SIMPLE], data["evidence"].map { |item| item["text"] }
      assert data["searches"].all? { |search| !search["query"].include?("lang:") }
    end
  end

  def test_explicit_multiple_languages_and_exclusions_can_be_combined
    data = run_with("比较数据分析工具 lang:zh,en，不要英文资料", rows: [result("english", ENGLISH, 3), result("traditional", TRADITIONAL, 2.9), result("simple", SIMPLE, 1.6)])
    assert data["searches"].all? { |search| search["query"].end_with?(" lang:zh,en") }
    assert_equal [TRADITIONAL, SIMPLE], data["evidence"].map { |item| item["text"] }
    refute data["sources"].find { |source| source["language"] == "en" }["read"]
  end

  def test_negated_only_does_not_create_a_language_lock
    ["Do not use only English sources; include original Chinese sources too", "Don't use only English sources for this answer"].each do |question|
      policy = Geo::Language.preference(question)
      refute policy["strict"], question
      assert_empty policy["codes"], question
    end
  end
end
