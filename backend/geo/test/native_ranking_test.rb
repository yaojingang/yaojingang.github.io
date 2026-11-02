# frozen_string_literal: true
require_relative "core_test"

class GeoNativeRankingTest < Minitest::Test
  include GeoFixtures
  BODY = "企业数据分析工具需要结合数据规模、团队协作和接入成本进行比较。"

  def row(name, score, authority = 3, **extra)
    { "url" => "https://#{name}.example.org/guide", "title" => "企业数据分析资料", "site_name" => name,
      "content" => BODY, "rerank_score" => score, "authority" => authority }.merge(extra.transform_keys(&:to_s))
  end

  def flow(&provider)
    base = transport
    client = Geo::DeepSeek.new(@config, @store, transport: lambda do |path, payload|
      response = base.call(path, payload)
      provider.call(path, payload, response)
    end)
    Geo::Pipeline.new(client, @store)
  end

  def test_native_default_ignores_local_weights_and_teaching_is_explicit_and_cache_separate
    rows = 7.times.map { |i| row("source#{i}", i == 6 ? 1.2 : 2.9 - i * 0.1, i >= 5 ? 4 : 1) }
    pipeline = flow { |path, _, response| path == "/v1/tools/search" ? [200, { "results" => rows }] : response }
    weights = Geo::Ranking::DEFAULT.transform_values { 0 }.merge("auth" => 50)
    native = pipeline.run("企业分析工具", weights: weights) { |*_| }
    assert_equal "api", native["ranking"]["mode"]
    assert_equal "deepseek-score-v1", native["ranking"]["method"]
    assert_equal (0..4).map { |i| "source#{i}" }, native["sources"].select { |s| s["read"] }.map { |s| s["site"] }
    calls = @calls.length
    cached = pipeline.run("企业分析工具", weights: Geo::Ranking::DEFAULT) { |*_| }
    assert cached["cached"]
    assert_equal calls, @calls.length
    assert_equal native["run_id"], cached["run_id"]
    teaching = pipeline.run("企业分析工具", weights: weights, ranking_mode: "teaching") { |*_| }
    refute teaching["cached"]
    assert_equal "source5", teaching["sources"].first["site"]
    refute teaching["sources"].find { |s| s["site"] == "source6" }["read"]
    refute_equal native["run_id"], teaching["run_id"]
  end

  def test_unknown_authority_and_date_do_not_demote_a_native_high_score
    pipeline = flow { |path, _, response| path == "/v1/tools/search" ? [200, { "results" => [row("high", 2.9, -1), row("low", 1.8, 4, date: "2026-11-01")] }] : response }
    data = pipeline.run("企业分析工具") { |*_| }
    assert_equal "high", data["sources"].first["site"]
    assert_nil data["sources"].first["sig"][1]
    assert_nil data["sources"].first["sig"][2]
    assert data["sources"].first["read"]
  end

  def test_native_selection_checks_the_next_candidate_after_an_unusable_page
    rows = [row("navigation", 3, 3, content: "首页\n登录\n联系我们")] + 5.times.map { |i| row("valid#{i}", 2.9 - i * 0.1) }
    pipeline = flow { |path, _, response| path == "/v1/tools/search" ? [200, { "results" => rows }] : response }
    data = pipeline.run("企业分析工具") { |*_| }
    assert_equal 5, data["quality"]["read_count"]
    refute data["sources"].find { |s| s["site"] == "navigation" }["read"]
    assert_includes data["sources"].select { |s| s["read"] }.map { |s| s["site"] }, "valid4"
    refute data["quality"]["supplement_searched"]
  end

  def test_occurrences_original_lengths_raw_responses_and_counts_are_retained
    index = 0
    first = [row("a", 1.6, 3, title: "长" * 450, content: BODY * 700, site_icon: "https://a.example.org/icon.png", date: "2026-11-01T12:30:00Z"),
             { "url" => "javascript:alert(1)" }, 42, row("b", 2.8)]
    second = [row("b", 2.7), row("a", 2.5)]
    pipeline = flow do |path, _, response|
      if path == "/v1/tools/search"
        index += 1
        [200, { "results" => index == 1 ? first : second }]
      else
        response
      end
    end
    data = pipeline.run("企业分析工具") { |*_| }
    assert_equal [6, 2], [data["total"], data["dedup"]]
    assert_equal [4, 2, 2], data["processing"].values_at("accepted_occurrences", "skipped_occurrences", "duplicate_occurrences")
    a = data["sources"].find { |s| s["site"] == "a" }
    assert_equal 2, a["hits"]
    assert_equal [1, 2], a["occurrences"].map { |o| o["query_index"] }
    assert_equal [1, 2], a["occurrences"].map { |o| o["raw_rank"] }
    assert_includes a["occurrences"][0]["truncated_fields"], "title"
    assert_includes a["occurrences"][0]["truncated_fields"], "content"
    assert_equal 450, a["occurrences"][0]["original_lengths"]["title"]
    record = @store.diagnostics.read(data["run_id"])
    assert record["complete"]
    calls = record["events"].select { |event| event["event"] == "upstream" }.map { |event| event["data"] }
    searches = calls.select { |call| call["kind"] == "search" }
    assert_equal first, searches.first["response"]["results"]
    assert_equal "https://a.example.org/icon.png", searches.first["response"]["results"][0]["site_icon"]
    assert_equal ["unsupported_scheme", "invalid_item"], data["processing"]["merges"][0]["skipped"].map { |r| r["reason"] }
    refute_includes record.to_json, @config.api_key
    refute_includes record.to_json, "fixture-password-123"
    assert_in_delta data["budget"]["used_cny"], data["diagnostics"]["settled_cny"], 0.000001
    assert calls.all? { |call| call["elapsed_seconds"].is_a?(Numeric) && call["charge_id"] }
    assert_equal 0600, File.stat(@store.diagnostics.path(data["run_id"])).mode & 0777
  end

  def test_wrong_language_expansion_falls_back_without_an_extra_model_call
    pipeline = flow do |path, payload, response|
      if path == "/chat/completions" && payload["max_tokens"] == 600
        response[1]["choices"][0]["message"]["content"] = JSON.generate("queries" => ["企业分析工具", "data analysis tools for teams"])
      end
      response
    end
    data = pipeline.run("企业分析工具") { |*_| }
    assert_equal ["企业分析工具 lang:zh"], data["searches"].map { |s| s["query"] }
    assert_equal 2, @calls.count { |path, _| path == "/chat/completions" }
  end

  def test_english_queries_can_keep_chinese_named_entities
    policy = Geo::Language.preference("Compare 腾讯云 and 阿里云 for our team")
    assert Geo::Language.query_matches?("Compare 腾讯云 and 阿里云 cloud tools", policy, entities: ["腾讯云", "阿里云"])
    refute Geo::Language.query_matches?("企业数据分析工具对比", policy, entities: ["腾讯云", "阿里云"])
  end

  def test_unknown_mode_is_rejected_before_paid_calls
    error = assert_raises(Geo::Error) { pipeline.run("企业分析工具", ranking_mode: "unknown") { |*_| } }
    assert_equal "invalid_ranking_mode", error.code
    assert_empty @calls
  end

  def test_deep_plan_metadata_cannot_make_optional_logging_abort_the_answer
    nested = "leaf"
    99.times { nested = { "x" => nested } }
    pipeline = flow do |path, payload, response|
      if path == "/chat/completions" && payload["max_tokens"] == 600
        response[1]["choices"][0]["message"]["content"] = JSON.generate({ "queries" => ["企业分析工具"], "extra" => nested }, max_nesting: false)
      end
      response
    end
    data = pipeline.run("企业分析工具") { |*_| }
    assert_equal "complete", data["status"]
    refute data["diagnostics"]["complete"]
    assert @store.diagnostics.read(data["run_id"])["events"].any? { |e| e["event"] == "result" }
  end

  def test_pipeline_validation_errors_are_in_the_private_run_record
    error = assert_raises(Geo::Error) { pipeline(invalid_citation: true).run("企业分析工具") { |*_| } }
    assert_equal "invalid_citation", error.code
    file = Dir.glob(File.join(@directory, "diagnostics", "*.jsonl")).first
    record = @store.diagnostics.read(File.basename(file, ".jsonl"))
    assert record["events"].any? { |event| event["event"] == "error" && event["data"]["code"] == "invalid_citation" }
    assert_equal "failed", record["events"].last["data"]["status"]
  end

  def test_anomalous_observed_cost_matches_the_ledger_instead_of_pending_reservation
    pipeline = flow do |_, _, response|
      response[1]["usage"] = { "prompt_tokens" => 1_000_000, "completion_tokens" => 80 }
      response
    end
    error = assert_raises(Geo::Error) { pipeline.run("企业分析工具") { |*_| } }
    assert_equal "price_limit", error.code
    file = Dir.glob(File.join(@directory, "diagnostics", "*.jsonl")).first
    call = @store.diagnostics.read(File.basename(file, ".jsonl"))["events"].find { |e| e["event"] == "upstream" }["data"]
    assert_equal "anomaly", call["charge_state"]
    assert_equal 2_000_640, call["settled_micros"]
    assert_in_delta @store.budget["used_cny"], call["settled_micros"] / 1_000_000.0, 0.000001
  end

  def test_recording_failure_is_reported_without_breaking_the_answer
    @store.instance_variable_set(:@diagnostics, Geo::Diagnostics.new(@directory, max_bytes: 0))
    data = pipeline.run("企业分析工具") { |*_| }
    assert_equal "complete", data["status"]
    refute data["diagnostics"]["complete"]
    refute data["diagnostics"]["available"]
    assert_operator data["budget"]["used_cny"], :>, 0
  end
end

class GeoDiagnosticsTest < Minitest::Test
  include GeoFixtures

  def test_expired_records_and_capacity_are_bounded_while_active_runs_are_kept
    now = Time.now
    logs = Geo::Diagnostics.new(@directory, retention: 10, max_bytes: 1200, clock: -> { now })
    old = logs.start("question" => "a" * 300)
    old.finish("complete")
    recent = logs.start("question" => "b" * 300)
    recent.finish("complete")
    newest = logs.start("question" => "c" * 300)
    newest.finish("complete")
    assert_operator Dir.glob(File.join(@directory, "diagnostics", "*.jsonl")).sum { |f| File.size(f) }, :<=, 1200
    assert logs.read(newest.id)["complete"]
    assert_raises(Geo::Error) { logs.read(old.id) }
    now += 11
    assert_raises(Geo::Error) { logs.read(newest.id) }
    active = logs.start("question" => "active")
    now += 11
    assert logs.read(active.id)
    active.finish("complete")
  end

  def test_invalid_run_ids_cannot_address_other_files
    ["../geo.sqlite3", "a" * 32 + ".json", "A" * 32, ""].each do |id|
      error = assert_raises(Geo::Error) { @store.diagnostics.read(id) }
      assert_equal "invalid_run", error.code
    end
  end
end
