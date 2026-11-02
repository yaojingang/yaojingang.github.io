# frozen_string_literal: true
require_relative "core_test"

class GeoSearchQualityTest < Minitest::Test
  include GeoFixtures

  def with_results(results)
    base = transport
    client = Geo::DeepSeek.new(@config, @store, transport: lambda do |path, payload|
      response = base.call(path, payload)
      path == "/v1/tools/search" ? [200, { "results" => results }] : response
    end)
    Geo::Pipeline.new(client, @store)
  end

  def source(score: 2.5, content: "根据数据规模和团队协作需求，选择适合企业的数据分析工具。", summary: "工具选择应比较数据规模、团队协作和接入成本。")
    { "url" => "https://example.org/analysis", "title" => "数据分析工具选型", "site_name" => "研究资料", "content" => content, "summary" => summary, "rerank_score" => score, "authority" => 3 }
  end

  def test_chinese_search_keeps_unicode_without_an_automatic_language_operator
    client = Geo::DeepSeek.new(@config, @store, transport: transport(no_results: true))
    client.search("数学分析师推荐", "数学分析师推荐")
    payload = @calls.last[1]
    assert_equal "数学分析师推荐", payload["query"]
    assert_equal "数学分析师推荐", payload["ori_question"]
  end

  def test_explicit_language_is_respected_and_query_stays_within_api_limit
    client = Geo::DeepSeek.new(@config, @store, transport: transport(no_results: true))
    client.search("数学 职业", "请查英文资料：数学职业 lang:en")
    assert_equal "数学 职业 lang:en", @calls.last[1]["query"]
    client.search("中" * 128, "只用中文资料")
    assert_operator @calls.last[1]["query"].length, :<=, 128
    assert @calls.last[1]["query"].end_with?(" lang:zh")
  end

  def test_first_query_preserves_the_original_question
    data = pipeline.run("数学分析师推荐") { |*_| }
    assert_equal "数学分析师推荐", data["searches"][0]["query"]
    queries = @calls.select { |path, _| path == "/v1/tools/search" }.map { |_, payload| payload["query"] }
    assert_equal queries, data["searches"].map { |item| item["query"] }
  end

  def test_low_scoring_foreign_results_do_not_become_recommendations
    result = source(score: 1.188, content: "Recherche\n\nAlumni\n\nCareer prospects for mathematicians", summary: "数学专业毕业生可以选择多个职业方向。")
    data = with_results([result]).run("数学分析师推荐") { |*_| }
    assert_equal "insufficient", data["status"]
    assert_empty data["answer"]
    assert_empty data["cited"]
    assert_empty data["evidence"]
    assert_equal 1, @calls.count { |path, _| path == "/chat/completions" }
    assert_equal 0, @calls.count { |path, _| path == "/v1/tools/fetch" }
    assert_match(/1.50/, data["sources"][0]["why"])
    assert_equal [0, 1, 2, 3, 4, 5], data["trace"].map { |step| step["stage"] }.uniq
  end

  def test_only_eligible_sources_are_read_and_threshold_is_inclusive
    lower = source(score: 1.49).merge("url" => "https://example.net/low")
    data = with_results([source(score: 1.5), lower]).run("选择数据分析工具") { |*_| }
    assert_equal 1, data["quality"]["read_count"]
    assert_equal 1, data["quality"]["eligible_count"]
    assert_equal ["S1"], data["evidence"].map { |item| item["source_id"] }.uniq
    assert_equal ["S1"], data["cited"]
    assert data["sources"][0]["read"]
    refute data["sources"][1]["read"]
  end

  def test_navigation_only_body_falls_back_to_labelled_summary
    result = source(content: "# Career prospects for mathematicians\n\nRecherche\n\nAlumni\n\n[News](https://example.org/news)")
    data = with_results([result]).run("选择数据分析工具") { |*_| }
    assert_equal "搜索摘要", data["sources"][0]["type"]
    assert data["evidence"].all? { |item| item["basis"] == "summary" }
    assert_equal result["summary"], data["evidence"][0]["text"]
    assert_equal result["summary"], data["answer"][0]["segs"][0]["f"][0]["q"]
  end

  def test_navigation_without_a_useful_summary_stops_before_answer_generation
    data = with_results([source(content: "Recherche\n\nAlumni", summary: "")]).run("数学分析师推荐") { |*_| }
    assert_equal "insufficient", data["status"]
    assert_empty data["evidence"]
    assert_equal 1, @calls.count { |path, _| path == "/chat/completions" }
  end

  def test_old_cached_answers_cannot_bypass_the_new_quality_gate
    question = "数学分析师推荐"
    @store.cache_put(Digest::SHA256.hexdigest("geo-live-1.1:#{question}"), { "status" => "old-unfiltered" })
    flow = with_results([source(score: 1.2)])
    fresh = flow.run(question) { |*_| }
    assert_equal "insufficient", fresh["status"]
    refute fresh["cached"]
    calls = @calls.length
    cached = flow.run(question) { |*_| }
    assert cached["cached"]
    assert_equal "insufficient", cached["status"]
    assert_equal calls, @calls.length
  end
  def test_language_exclusions_do_not_create_an_automatic_source_lock
    ["不要引用英文资料，请推荐数学分析师", "数学分析师推荐，不需要英文来源", "英文资料不要用，请查数学分析师"].each do |question|
      assert_nil Geo::DeepSeek.search_language(question)
    end
    assert_nil Geo::DeepSeek.search_language("不要只看中文，请提供英文资料")
  end

  def test_language_lists_are_deduplicated_and_oversize_input_is_rejected_before_paid_planning
    question = "数学资料推荐 lang:" + (["zh"] * 50).join(",")
    assert_equal "数学资料推荐 lang:zh", Geo::DeepSeek.search_query(question, question)
    codes = ("a".."z").to_a.product(("a".."z").to_a).first(50).map(&:join)
    error = assert_raises(Geo::Error) { pipeline.run("数学资料推荐 lang:" + codes.join(",")) { |*_| } }
    assert_equal 400, error.status
    assert_empty @calls
  end

  def test_single_newline_navigation_lists_are_not_body_evidence
    menus = ["首页\n课程介绍\n数学分析师\n专家推荐\n登录注册\n用户中心\n关于我们\n联系我们\n帮助中心\n网站地图",
             "Recherche\nAlumni\nAdmissions\nAcademics\nResearch centres\nStudent services\nCampus life\nInternational partnerships\nNews and events\nContact information\nEmployment opportunities"]
    menus.each_with_index do |menu, index|
      data = with_results([source(content: menu)]).run("数据分析工具推荐 #{index}") { |*_| }
      assert_equal "搜索摘要", data["sources"][0]["type"]
      assert data["evidence"].all? { |item| item["basis"] == "summary" }
    end
  end

  def test_a_filtered_summary_can_fall_back_to_the_existing_snippet
    snippet = "数学分析专家的选择需要结合研究方向、课程内容和公开发表的研究成果。"
    data = with_results([source(content: "首页", summary: "网站导航").merge("snippet" => snippet)]).run("数学分析师推荐") { |*_| }
    assert_equal "complete", data["status"]
    assert_equal snippet, data["evidence"][0]["text"]
    assert_equal "summary", data["evidence"][0]["basis"]
  end

  def test_all_provided_evidence_ids_can_be_used_without_an_arbitrary_three_id_limit
    paragraph = "企业选择分析工具时，应结合数据规模、团队协作需求和接入成本。"
    results = [source(content: ([paragraph] * 3).join("\n\n")), source(content: ([paragraph] * 3).join("\n\n")).merge("url" => "https://example.net/guide")]
    base = transport
    provider = lambda do |path, payload|
      response = base.call(path, payload)
      if path == "/v1/tools/search"
        [200, { "results" => results }]
      elsif path == "/chat/completions" && payload["max_tokens"] != 600
        evidence = JSON.parse(payload["messages"][1]["content"])["evidence"]
        value = { "paragraphs" => [{ "text" => paragraph, "evidence_ids" => evidence.map { |item| item["id"] } }] }
        response[1]["choices"][0]["message"]["content"] = JSON.generate(value)
        response
      else
        response
      end
    end
    flow = Geo::Pipeline.new(Geo::DeepSeek.new(@config, @store, transport: provider), @store)
    data = flow.run("企业数据分析工具怎么选择") { |*_| }
    assert_equal "complete", data["status"]
    assert_equal 6, data["evidence"].length
    assert_equal ["S1", "S2"], data["cited"]
    assert_equal 6, data["answer"][0]["segs"][0]["f"].length
    assert_equal data["evidence"].map { |e| e["id"] }, data["answer"][0]["segs"][0]["f"].map { |ref| ref["evidence_id"] }
  end

end
