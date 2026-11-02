# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/pipeline"

module GeoFixtures
  def setup
    @directory = Dir.mktmpdir("geo-test-")
    @config = Geo::Config.new(api_key: "sk-test-key-for-fixtures", password: "fixture-password-123", data_dir: @directory, file: File.join(@directory, "absent"))
    @store = Geo::Store.new(@directory)
    @calls = []
  end

  def teardown
    @store.close
    FileUtils.remove_entry(@directory)
  end

  def transport(invalid_citation: false, no_results: false, fetch_error: false)
    lambda do |path, payload|
      @calls << [path, payload]
      case path
      when "/chat/completions"
        if payload["max_tokens"] == 600
          value = { "intent" => "工具对比", "queries" => ["企业 数据分析 工具", "数据分析 选型"] }
        else
          evidence = JSON.parse(payload["messages"][1]["content"])["evidence"]
          value = { "paragraphs" => [{ "text" => "企业可以根据数据规模和协作需求选择工具。", "evidence_ids" => [invalid_citation ? "FORGED" : evidence[0]["id"]] }] }
        end
        [200, { "choices" => [{ "finish_reason" => "stop", "message" => { "content" => JSON.generate(value) } }], "usage" => { "prompt_tokens" => 100, "completion_tokens" => 80 } }]
      when "/v1/tools/search"
        results = no_results ? [] : [
          { "url" => "https://example.org/analysis#section", "title" => "企业数据分析指南", "site_name" => "研究资料", "snippet" => "按需求选择工具。", "summary" => "企业需要结合数据规模和协作需求。", "content" => "# 企业数据分析\n\n根据数据规模、团队协作需求选择数据分析工具。", "rerank_score" => 2.7, "authority" => 3, "date" => nil },
          { "url" => "https://example.net/guide", "title" => "数据工具说明", "summary" => "工具需要考虑协作成本。", "content" => "", "rerank_score" => 1.8, "authority" => -1 },
          { "url" => "javascript:alert(1)", "title" => "unsafe", "rerank_score" => 3 },
          { "url" => "http://127.0.0.1/admin", "title" => "private", "rerank_score" => 3 }
        ]
        [200, { "results" => results }]
      when "/v1/tools/fetch"
        fetch_error ? [404, { "error" => {} }] : [200, { "title" => "数据工具说明", "content" => "# 选型\n\n企业选择工具时应核对协作成本和接入成本。" }]
      else
        raise "Unexpected fixture endpoint"
      end
    end
  end

  def pipeline(**options)
    Geo::Pipeline.new(Geo::DeepSeek.new(@config, @store, transport: transport(**options)), @store)
  end

end

class GeoCoreTest < Minitest::Test
  include GeoFixtures

  def test_pipeline_records_real_counts_deduplicates_and_resolves_evidence
    events = []
    data = pipeline.run("企业如何选择数据分析工具？") { |event, value| events << [event, value] }
    assert_equal 8, data["total"]
    assert_equal 2, data["dedup"]
    assert_equal 2, data["sources"].length
    assert_equal [4, 4], data["searches"].map { |s| s["count"] }
    assert_equal ["S1"], data["cited"]
    reference = data["answer"][0]["segs"][0]["f"][0]
    assert data["evidence"].any? { |item| item["id"] == reference["evidence_id"] && item["text"] == reference["q"] }
    assert_equal "body", reference["basis"]
    assert_equal "日期未知", data["sources"][0]["date"]
    assert_equal 1, @calls.count { |path, _| path == "/v1/tools/fetch" }
    assert_equal [0, 1, 2, 3, 4, 5], events.map { |_, value| value["stage"] }.uniq
    refute data.to_json.include?("sk-test-key-for-fixtures")
    assert_operator data["budget"]["used_cny"], :>, 0
  end

  def test_cache_reuses_result_without_another_paid_call
    first = pipeline.run("选择数据分析工具") { |*_| }
    cost = @store.budget["used_cny"]
    calls = @calls.length
    cached = pipeline.run("选择数据分析工具") { |*_| }
    assert cached["cached"]
    assert_equal first["created_at"], cached["created_at"]
    assert_equal calls, @calls.length
    assert_equal cost, @store.budget["used_cny"]
  end

  def test_a_forged_citation_is_rejected
    error = assert_raises(Geo::Error) { pipeline(invalid_citation: true).run("选择数据分析工具") { |*_| } }
    assert_equal "invalid_citation", error.code
  end

  def test_fetch_failure_preserves_summary_label_and_actual_warning
    data = pipeline(fetch_error: true).run("选择数据分析工具") { |*_| }
    assert_equal "搜索摘要", data["sources"][1]["type"]
    assert data["evidence"].any? { |item| item["basis"] == "summary" }
    assert_equal 1, data["warnings"].length
  end

  def test_no_results_stops_before_fetch_and_answer_generation
    data = pipeline(no_results: true).run("一个没有结果的问题") { |*_| }
    assert_equal "insufficient", data["status"]
    assert_empty data["answer"]
    assert_equal 0, data["quality"]["read_count"]
    assert_equal 3, @calls.length
  end

  def test_budget_is_atomic_and_survives_a_restart
    store = Geo::Store.new(File.join(@directory, "budget"), limit: 50)
    outcomes = 6.times.map do
      Thread.new do
        begin
          store.reserve("search", 20)
          :ok
        rescue Geo::Error
          :blocked
        end
      end
    end.map(&:value)
    assert_equal 2, outcomes.count(:ok)
    assert_equal 4, outcomes.count(:blocked)
    store.close
    reopened = Geo::Store.new(File.join(@directory, "budget"), limit: 50)
    assert_in_delta 0.00004, reopened.budget["used_cny"], 0.0000001
    assert_raises(Geo::Error) { reopened.reserve("search", 20) }
    reopened.close
  end

  def test_an_unknown_network_result_keeps_its_reservation_and_is_not_retried
    attempts = 0
    client = Geo::DeepSeek.new(@config, @store, transport: ->(*) { attempts += 1; raise Timeout::Error })
    assert_raises(Geo::Error) { client.search("数据分析", "数据分析") }
    assert_equal 1, attempts
    assert_in_delta 0.005, @store.budget["used_cny"], 0.000001
  end

  def test_authentication_failure_releases_unbilled_reservation
    client = Geo::DeepSeek.new(@config, @store, transport: ->(*) { [401, { "error" => {} }] })
    error = assert_raises(Geo::Error) { client.search("数据分析", "数据分析") }
    assert_equal "invalid_key", error.code
    assert_equal 0, @store.budget["used_cny"]
  end

  def test_unexpected_usage_is_recorded_and_halts_paid_calls_across_restart
    reservation = @store.reserve("model", 1000)
    assert_raises(Geo::Error) { @store.settle(reservation, 60_000_000) }
    assert_equal 60, @store.budget["used_cny"]
    assert_raises(Geo::Error) { @store.reserve("search", 5000) }
    @store.close
    @store = Geo::Store.new(@directory)
    assert_raises(Geo::Error) { @store.reserve("search", 5000) }
  end

  def test_sessions_store_a_hash_and_logout_revokes_them
    token = @store.session_create
    assert @store.session_valid?(token)
    refute @store.session_valid?("x" * 64)
    @store.session_delete(token)
    refute @store.session_valid?(token)
  end

  def test_input_and_url_boundaries
    %w[javascript:alert(1) http://localhost/a http://169.254.169.254/latest http://10.0.0.1/a https://user:pass@example.org/a].each { |url| assert_nil pipeline.public_url(url) }
    assert_equal "https://example.org/a", pipeline.public_url("https://example.org/a#section")
    [nil, "", " " * 5, "中" * 501, { "query" => "a" }].each { |value| assert_raises(Geo::Error) { Geo::Pipeline.question(value) } }
    assert_equal "问题", Geo::Pipeline.question(" 问题 ")
  end

  def test_missing_model_usage_keeps_the_conservative_reservation
    client = Geo::DeepSeek.new(@config, @store, transport: ->(*) { [200, { "choices" => [{ "finish_reason" => "stop", "message" => { "content" => '{"ok":true}' } }] }] })
    assert client.json("返回 JSON", "测试", 100)["ok"]
    assert_operator @store.budget["used_cny"], :>, 0.005
  end

  def test_local_paid_calls_are_retired_after_server_installation
    reservation = @store.reserve("model", 1234)
    assert_equal 1234, @store.retire_local!
    assert_raises(Geo::Error) { @store.reserve("search", 5000) }
    @store.settle(reservation, 1000)
    assert @config.credentials_present?
    refute @config.configured?
    error = assert_raises(Geo::Error) { pipeline.run("测试本机付费关闭") { |*_| } }
    assert_equal "not_configured", error.code
    assert_empty @calls
    assert_in_delta 0.001, @store.budget["used_cny"], 0.0000001
  end

  def test_local_verification_cost_carries_into_the_initial_server_budget_once
    directory = File.join(@directory, "seeded")
    seeded = Geo::Store.new(directory, initial_spend: 21_702)
    assert_in_delta 0.021702, seeded.budget["used_cny"], 0.0000001
    seeded.close
    restarted = Geo::Store.new(directory, initial_spend: 21_702)
    assert_in_delta 0.021702, restarted.budget["used_cny"], 0.0000001
    restarted.close
  end
end
