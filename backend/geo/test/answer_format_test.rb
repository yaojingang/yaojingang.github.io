# frozen_string_literal: true
require_relative "core_test"

class GeoAnswerFormatTest < Minitest::Test
  include GeoFixtures

  def formatted(rows)
    base = transport
    provider = lambda do |path, payload|
      response = base.call(path, payload)
      if path == "/chat/completions" && payload["max_tokens"] == 3000
        evidence = JSON.parse(payload["messages"][1]["content"])["evidence"]
        paragraphs = rows.map { |row| row.key?("evidence_ids") ? row : row.merge("evidence_ids" => [evidence.first["id"]]) }
        response[1]["choices"][0]["message"]["content"] = JSON.generate("paragraphs" => paragraphs)
      end
      response
    end
    Geo::Pipeline.new(Geo::DeepSeek.new(@config, @store, transport: provider), @store)
  end

  def test_summary_sections_lists_and_emphasis_keep_exact_text_and_evidence_links
    rows = [
      {"kind" => "summary", "text" => "选型应结合数据规模、团队协作和接入成本，先确认核心需求。", "emphasis" => ["数据规模", "核心需求"]},
      {"kind" => "paragraph", "heading" => "先确认使用场景", "text" => "团队协作需要核对使用人数和权限管理需求。", "emphasis" => ["使用人数"]},
      {"kind" => "bullet", "text" => "接入成本应同时考虑数据源连接和日常维护。", "emphasis" => ["接入成本"]}
    ]
    data = formatted(rows).run("企业如何选择分析工具？") { |*_| }
    assert_equal %w[summary paragraph bullet], data["answer"].map { |block| block["kind"] }
    assert_equal "先确认使用场景", data["answer"][1]["heading"]
    assert_equal rows.map { |row| row["text"] }, data["answer"].flat_map { |block| block["segs"].map { |seg| seg["x"] } }
    assert_equal ["数据规模", "核心需求"], data["answer"][0]["segs"][0]["em"]
    data["answer"].each do |block|
      block["segs"][0]["f"].each do |ref|
        assert data["evidence"].any? { |e| e["id"] == ref["evidence_id"] && e["text"] == ref["q"] }
      end
    end
  end

  def test_emphasis_is_limited_to_short_exact_phrases_and_one_third_of_text
    text = "企业应比较数据规模、团队协作需求、接入成本与长期维护成本。"
    rows = [{"text" => text, "emphasis" => [text, "不存在的短语", nil, 3, "数据规模", "数据规模", "团队协作", "接入成本"]}]
    marks = formatted(rows).run("企业数据分析工具选型") { |*_| }["answer"][0]["segs"][0]["em"]
    assert_equal ["数据规模", "团队协作"], marks
    assert_operator marks.sum(&:length), :<=, text.length / 3
  end

  def test_unknown_optional_format_fields_fall_back_without_losing_factual_text
    rows = [
      {"kind" => "unexpected", "heading" => "忽略首段标题", "text" => "分析工具的选择需要结合团队协作和数据规模。", "emphasis" => {"bad" => "shape"}},
      {"kind" => [], "heading" => "长" * 61, "text" => "接入成本和维护成本需要分别核对。", "emphasis" => ["维护成本"]}
    ]
    answer = formatted(rows).run("分析工具选择需要注意什么") { |*_| }["answer"]
    assert_equal %w[summary paragraph], answer.map { |block| block["kind"] }
    assert answer.all? { |block| block["heading"].nil? }
    assert_empty answer[0]["segs"][0]["em"]
    assert_equal rows.map { |row| row["text"] }, answer.flat_map { |block| block["segs"].map { |seg| seg["x"] } }
  end

  def test_format_fields_cannot_bypass_citation_validation
    flow = formatted([{"kind" => "summary", "heading" => "标题", "text" => "需要结合团队的实际情况选择分析工具。", "emphasis" => ["实际情况"], "evidence_ids" => ["FORGED"]}])
    error = assert_raises(Geo::Error) { flow.run("选择分析工具") { |*_| } }
    assert_equal "invalid_citation", error.code
  end

  def test_old_flat_answer_cache_is_not_used_and_new_format_is_cached
    question = "企业如何选择数据分析工具？"
    old_key = Digest::SHA256.hexdigest("geo-live-1.4.1:#{question}:#{JSON.generate(Geo::Ranking::DEFAULT)}")
    @store.cache_put(old_key, {"status" => "old-flat-answer"})
    flow = formatted([{"text" => "企业选择数据分析工具时需要核对团队协作与接入成本。"}])
    data = flow.run(question) { |*_| }
    assert_equal "summary", data["answer"][0]["kind"]
    refute data["cached"]
    calls = @calls.length
    cached = flow.run(question) { |*_| }
    assert cached["cached"]
    assert_equal calls, @calls.length
  end
end
