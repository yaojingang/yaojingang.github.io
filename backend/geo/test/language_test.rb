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

  def run_with(question, primary:, fallback: [], fetch: nil, weights: nil)
    base = transport
    client = Geo::DeepSeek.new(@config, @store, transport: lambda do |path, payload|
      response = base.call(path, payload)
      if path == "/v1/tools/search"
        [200, { "results" => payload["query"].include?(" lang:") ? primary : fallback }]
      elsif path == "/v1/tools/fetch" && fetch
        [200, { "content" => fetch }]
      else
        response
      end
    end)
    Geo::Pipeline.new(client, @store).run(question, weights: weights) { |*_| }
  end

  def test_detects_question_language_and_script_with_mixed_technical_names
    { "How does Google Search discover and index pages?" => "en", "数据分析工具推荐" => "zh-Hans",
      "資料分析工具推薦" => "zh-Hant", "DeepSeek API 怎么用？" => "zh-Hans", "DeepSeek API 如何使用？" => "zh-Hans",
      "Compare 腾讯云 and 阿里云 for our team" => "en", "你好" => "zh-Hans" }.each do |question, expected|
      assert_equal expected, Geo::Language.preference(question)["preferred"], question
    end
    assert_equal "zh", Geo::Language.detect("人工智能方法")
    assert_equal "ja", Geo::Language.detect("これは日本語の資料です。")
    assert_equal "other", Geo::Language.detect("Recherche et informations sur les études mathématiques.")
    assert_equal "unknown", Geo::Language.detect("123 / ++")
  end

  def test_english_search_has_a_language_operator_by_default
    assert_equal "Google Search lang:en", Geo::DeepSeek.search_query("Google Search", "How does Google Search work?")
    assert_equal "Google 搜索", Geo::DeepSeek.search_query("Google 搜索 lang:zh", "搜索", language: nil)
    assert_equal "zh", Geo::DeepSeek.search_language("資料分析工具推薦")
  end

  def test_matching_simple_sources_beat_higher_weighted_traditional_and_english_sources
    rows = [result("simple", SIMPLE, 1.6), result("traditional", TRADITIONAL, 2.9), result("english", ENGLISH, 3)]
    data = run_with("数据分析工具怎么选择？", primary: rows)
    assert_equal ["zh-Hans"], data["sources"].select { |s| s["read"] }.map { |s| s["language"] }
    assert_equal 2, data["searches"].length
    refute data["quality"]["supplement_searched"]
    refute data["quality"]["language_fallback"]
    assert_equal "zh-Hans", data["quality"]["preferred_language"]
    assert_equal "zh-Hans", data["sources"].first["language"]
    refute data["sources"].last["language_allowed"]
    assert_equal [SIMPLE], data["evidence"].map { |e| e["text"] }
    auth = Geo::Ranking::DEFAULT.merge("auth" => 50)
    preview = Geo::Ranking.order(Marshal.load(Marshal.dump(data["sources"])), auth)
    assert_equal "zh-Hans", preview.first["language"]
    refute Geo::Ranking.selectable?(preview.last)
  end

  def test_traditional_input_prefers_traditional_sources
    data = run_with("資料分析工具應該怎麼選擇？", primary: [result("simple", SIMPLE, 3), result("traditional", TRADITIONAL, 1.6)])
    assert_equal "zh-Hant", data["quality"]["preferred_language"]
    assert_equal [TRADITIONAL], data["evidence"].map { |e| e["text"] }
    assert_equal "繁体中文", data["sources"].first["language_label"]
    refute data["quality"]["language_fallback"]
  end

  def test_english_input_uses_english_sources_and_answer_language
    data = run_with("How should our team choose data analysis tools?", primary: [result("simple", SIMPLE, 3), result("english", ENGLISH, 1.6)])
    assert_equal [ENGLISH], data["evidence"].map { |e| e["text"] }
    assert data["searches"].all? { |row| row["query"].end_with?(" lang:en") }
    input = JSON.parse(@calls.reverse.find { |path, payload| path == "/chat/completions" && payload["max_tokens"] == 3000 }[1]["messages"][1]["content"])
    assert_equal "en", input["response_language"]
  end

  def test_missing_preferred_sources_adds_only_one_unrestricted_search_and_uses_other_script_first
    data = run_with("数据分析工具怎么选择？", primary: [result("english", ENGLISH, 3)], fallback: [result("traditional", TRADITIONAL, 1.6)])
    assert_equal 3, data["searches"].length
    assert_equal "supplement", data["searches"].last["phase"]
    refute_includes data["searches"].last["query"], "lang:"
    assert_equal "zh-Hant", data["sources"].first["language"]
    assert data["quality"]["language_fallback"]
    assert data["sources"].select { |s| s["read"] }.all? { |s| s["language_supplement"] }
    assert_match(/补充信源/, data["warnings"].last)
  end

  def test_no_relevant_preferred_results_triggers_supplement_without_lowering_quality_threshold
    data = run_with("数据分析工具怎么选择？", primary: [result("simple", SIMPLE, 1.49)], fallback: [result("english", ENGLISH)])
    assert data["quality"]["supplement_searched"]
    assert_equal [ENGLISH], data["evidence"].map { |e| e["text"] }
    refute data["sources"].find { |s| s["language"] == "zh-Hans" }["read"]
  end

  def test_fetch_reveals_a_different_language_then_supplements
    data = run_with("数据分析工具怎么选择？", primary: [result("masked", "", 2.8, title: "数据分析工具推荐")],
      fallback: [result("english", ENGLISH)], fetch: ENGLISH)
    assert data["quality"]["supplement_searched"]
    assert_equal [ENGLISH], data["evidence"].map { |e| e["text"] }.uniq
    assert_equal 1, @calls.count { |path, _| path == "/v1/tools/fetch" }
    assert_equal 2, data["quality"]["read_count"]
  end

  def test_unusable_preferred_body_and_summaries_trigger_supplement
    data = run_with("数据分析工具怎么选择？", primary: [result("navigation", "数据分析\n首页\n联系我们")], fallback: [result("english", ENGLISH)])
    assert data["quality"]["supplement_searched"]
    assert_equal [ENGLISH], data["evidence"].map { |e| e["text"] }
    assert_equal 2, data["quality"]["attempted_count"]
    refute data["sources"].find { |s| s["url"].include?("navigation") }["read"]
  end

  def test_strict_language_request_never_broadens_or_uses_foreign_content
    ["只用简体中文资料，数据分析工具怎么选择？", "数据分析工具推荐 lang:zh"].each do |question|
      rows = question.include?("lang:zh") ? [result("english", ENGLISH)] : [result("traditional", TRADITIONAL)]
      data = run_with(question, primary: rows, fallback: [result("foreign", ENGLISH)])
      assert_equal "insufficient", data["status"]
      assert_equal 2, data["searches"].length
      refute data["quality"]["supplement_searched"]
      assert_empty data["evidence"]
    end
  end

  def test_new_preferred_content_found_during_supplement_displaces_foreign_content
    data = run_with("数据分析工具怎么选择？", primary: [], fallback: [result("simple", SIMPLE, 1.6), result("english", ENGLISH, 3)])
    assert data["quality"]["supplement_searched"]
    refute data["quality"]["language_fallback"]
    assert_equal [SIMPLE], data["evidence"].map { |e| e["text"] }
    refute data["sources"].find { |s| s["language"] == "en" }["read"]
  end
  def test_natural_language_limits_select_the_requested_language
    chinese = Geo::Language.preference("Use only Chinese sources for data analysis tools.")
    assert_equal "zh", chinese["preferred"]
    assert chinese["strict"]
    english = Geo::Language.preference("只使用英文的资料，数据分析工具怎么选择？")
    assert_equal "en", english["preferred"]
    assert english["strict"]
    data = run_with("Use only Chinese sources for data analysis tools.", primary: [result("simple", SIMPLE), result("english", ENGLISH)])
    assert_equal [SIMPLE], data["evidence"].map { |e| e["text"] }
  end

  def test_explicitly_excluded_languages_stay_excluded_during_supplementation
    ["不要引用英文资料，请推荐数据分析工具", "英文资料不要用，请推荐数据分析工具"].each do |question|
      data = run_with(question, primary: [], fallback: [result("english", ENGLISH)])
      assert_empty data["evidence"], question
      assert_equal "insufficient", data["status"]
      refute data["sources"].first["language_allowed"]
    end
  end

  def test_already_fetched_foreign_evidence_can_be_reused_when_supplement_has_no_new_urls
    data = run_with("数据分析工具怎么选择？", primary: [result("masked", "", 2.8, title: "数据分析工具推荐")],
      fallback: [], fetch: ENGLISH)
    assert_equal "complete", data["status"]
    assert_equal [ENGLISH], data["evidence"].map { |e| e["text"] }
    assert_equal 1, @calls.count { |path, _| path == "/v1/tools/fetch" }
  end

  def test_navigation_body_does_not_hide_preferred_summary
    data = run_with("数据分析工具怎么选择？", primary: [result("simple", "Home\nAbout\nContact\nLogin", 2.8, summary: SIMPLE)],
      fallback: 5.times.map { |i| result("english#{i}", ENGLISH, 3) })
    assert_equal [SIMPLE], data["evidence"].map { |e| e["text"] }
    refute data["quality"]["supplement_searched"]
  end

  def test_unknown_enabled_scores_sort_after_selectable_candidates_before_language_grouping
    weights = Geo::Ranking::DEFAULT.keys.each_with_object({}) { |key, hash| hash[key] = key == "auth" ? 50 : 0 }
    data = run_with("数据分析工具怎么选择？", primary: [result("simple", SIMPLE, 2.8, authority: -1)],
      fallback: [result("english", ENGLISH)], weights: weights)
    assert_equal "en", data["sources"].first["language"]
    assert data["sources"].first["read"]
    assert_nil data["sources"].last["weighted_score"]
  end

  def test_shared_traditional_characters_do_not_cancel_distinct_traditional_signals
    ["台灣教育", "台灣生活", "台灣美食", "台灣AI", "發布資料", "雲端服務的使用規范", "搜尋引擎", "我們", "什麼是AI", "兩個方案", "區塊鏈"].each do |question|
      assert_equal "zh-Hant", Geo::Language.preference(question)["preferred"], question
    end
  end

  def test_higher_score_duplicate_keeps_already_fetched_valid_body
    primary = result("masked", "", 2.0, title: "数据分析工具推荐")
    duplicate = primary.merge("rerank_score" => 2.9)
    data = run_with("数据分析工具怎么选择？", primary: [primary], fallback: [duplicate], fetch: ENGLISH)
    assert_equal "complete", data["status"]
    assert_equal [ENGLISH], data["evidence"].map { |e| e["text"] }
    assert_equal 1, @calls.count { |path, _| path == "/v1/tools/fetch" }
    assert_equal 2.9, data["sources"].first["api_score"]
  end

  def test_duplicate_navigation_does_not_replace_already_fetched_substantive_body
    primary = result("masked", "", 2.0, title: "数据分析工具推荐")
    duplicate = primary.merge("rerank_score" => 2.9, "content" => "Home\nAbout\nContact\nLogin")
    data = run_with("数据分析工具怎么选择？", primary: [primary], fallback: [duplicate], fetch: ENGLISH)
    assert_equal "complete", data["status"]
    assert_equal [ENGLISH], data["evidence"].map { |e| e["text"] }
    assert_equal 1, @calls.count { |path, _| path == "/v1/tools/fetch" }
  end

  def test_negated_only_does_not_create_an_english_language_lock
    ["Do not use only English sources; include original Chinese sources too", "Don't use only English sources for this answer"].each do |question|
      refute Geo::Language.preference(question)["strict"], question
    end
  end

  def test_supplement_can_reach_other_languages_after_preferred_title_only_fetches_fail
    base = transport
    fetches = 0
    client = Geo::DeepSeek.new(@config, @store, transport: lambda do |path, payload|
      response = base.call(path, payload)
      if path == "/v1/tools/search"
        prefix = payload["query"].include?(" lang:") ? "primary" : "supplement"
        rows = 10.times.map { |n| result("#{prefix}#{n}", "", 2.9, title: prefix == "primary" ? "数据分析工具推荐" : "The official guide for data tools") }
        [200, { "results" => rows }]
      elsif path == "/v1/tools/fetch"
        fetches += 1
        [200, { "content" => payload["url"].include?("primary") ? "首页\n联系我们" : ENGLISH }]
      else
        response
      end
    end)
    data = Geo::Pipeline.new(client, @store).run("数据分析工具怎么选择？") { |*_| }
    assert_equal "complete", data["status"]
    assert_equal 5, data["quality"]["read_count"]
    assert_equal 10, fetches
    assert_equal [ENGLISH], data["evidence"].map { |e| e["text"] }.uniq
    assert data["sources"].select { |s| s["read"] }.all? { |s| s["language"] == "en" }
  end

end
