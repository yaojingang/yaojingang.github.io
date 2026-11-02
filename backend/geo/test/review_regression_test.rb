# frozen_string_literal: true
require_relative "core_test"

class GeoReviewRegressionTest < Minitest::Test
  include GeoFixtures

  def planned(queries, **extra)
    base = transport
    client = Geo::DeepSeek.new(@config, @store, transport: lambda do |path, payload|
      response = base.call(path, payload)
      if path == "/chat/completions" && payload["max_tokens"] == 600
        plan = { "queries" => queries }.merge(extra.transform_keys(&:to_s))
        response[1]["choices"][0]["message"]["content"] = JSON.generate(plan)
      end
      response
    end)
    Geo::Pipeline.new(client, @store)
  end

  def long_question
    "企业需要比较多种工具的协作与部署能力，" * 8 + "核心对象是FineBI和Power BI。"
  end

  def test_invalid_language_plan_cannot_truncate_a_long_question_and_drop_its_entities
    flow = planned(["data analysis tools for enterprise teams"])
    error = assert_raises(Geo::Error) { flow.run(long_question) { |*_| } }
    assert_equal "invalid_plan", error.code
    assert_empty @calls.select { |path, _| path == "/v1/tools/search" }
    assert_equal 1, @calls.count { |path, _| path == "/chat/completions" }
  end

  def test_a_long_question_uses_only_valid_planned_queries
    query = "FineBI 和 Power BI 企业团队协作接入对比"
    data = planned([query, "data analysis tools for enterprise teams"]).run(long_question) { |*_| }
    assert_equal [query + " lang:zh"], data["searches"].map { |search| search["query"] }
    assert_equal "complete", data["status"]
  end

  def test_a_short_question_keeps_its_original_query_after_a_language_mismatch
    data = planned(["data analysis tools for enterprise teams"]).run("企业分析工具") { |*_| }
    assert_equal ["企业分析工具 lang:zh"], data["searches"].map { |search| search["query"] }
    assert_equal "complete", data["status"]
  end

  def test_cached_results_refresh_diagnostic_availability_without_paid_calls
    original = pipeline.run("企业分析工具缓存清理") { |*_| }
    file = @store.diagnostics.path(original["run_id"])
    assert original["diagnostics"]["available"]
    assert File.file?(file)
    @store.diagnostics.instance_variable_set(:@max_bytes, File.size(file))
    newer = @store.diagnostics.start("purpose" => "capacity regression")
    newer.finish("complete")
    refute File.file?(file)
    calls = @calls.length
    budget = @store.budget
    cached = pipeline.run("企业分析工具缓存清理") { |*_| }
    assert cached["cached"]
    refute cached["diagnostics"]["available"]
    assert_equal calls, @calls.length
    assert_equal budget, @store.budget
    assert_equal original["answer"], cached["answer"]
  end

  def test_expired_record_is_not_advertised_as_available
    original = pipeline.run("企业分析工具缓存过期") { |*_| }
    file = @store.diagnostics.path(original["run_id"])
    assert File.file?(file)
    expired = Time.now - Geo::Diagnostics::RETENTION - 1
    File.utime(expired, expired, file)
    cached = pipeline.run("企业分析工具缓存过期") { |*_| }
    assert cached["cached"]
    refute cached["diagnostics"]["available"]
    refute File.file?(file)
  end

  def test_upstream_credential_echo_is_removed_from_private_records
    client = Geo::DeepSeek.new(@config, @store, transport: ->(*) { [401, { "error" => { "message" => "Invalid API key: #{@config.api_key}" } }] })
    flow = Geo::Pipeline.new(client, @store)
    error = assert_raises(Geo::Error) { flow.run("企业分析工具") { |*_| } }
    assert_equal "invalid_key", error.code
    record = @store.diagnostics.read(flow.run_id)
    upstream = record["events"].find { |event| event["event"] == "upstream" }
    refute_nil upstream
    assert_includes upstream["data"]["response"]["error"]["message"], "Invalid API key:"
    refute_includes record.to_json, @config.api_key
    refute_includes File.read(@store.diagnostics.path(flow.run_id)), @config.api_key
    assert_equal 0, @store.budget["used_cny"]
  end

  def test_planning_and_result_records_also_redact_credentials
    secret = @config.password
    data = planned(["企业分析工具"], answer_plan: "检查工具资料 #{secret}").run("企业分析工具") { |*_| }
    assert_equal "complete", data["status"]
    assert_includes data["intent"]["plan"], "检查工具资料"
    refute_includes data["intent"]["plan"], secret
    record = @store.diagnostics.read(data["run_id"])
    assert record["events"].any? { |event| event["event"] == "plan" }
    assert record["events"].any? { |event| event["event"] == "result" }
    refute_includes record.to_json, secret
    refute_includes File.read(@store.diagnostics.path(data["run_id"])), secret
  end

  def test_redaction_covers_nested_values_and_json_escapes_without_mutating_input
    password = "口令-\"quoted\"-\\slash-123"
    config = Geo::Config.new(api_key: @config.api_key, password: password, data_dir: @directory, file: File.join(@directory, "absent"))
    input = { password => ["normal text", { "message" => "Invalid API key: #{config.api_key}" },
                          JSON.generate("plan" => password), JSON.generate({ "plan" => password }, ascii_only: true)], "usage" => 123 }
    before = Marshal.dump(input)
    result = config.redact_secrets(input)
    assert_equal before, Marshal.dump(input)
    assert_equal 123, result["usage"]
    assert_equal "normal text", result["[REDACTED]"][0]
    assert_equal "Invalid API key: [REDACTED]", result["[REDACTED]"][1]["message"]
    result["[REDACTED]"][2..3].each { |content| assert_equal "[REDACTED]", JSON.parse(content)["plan"] }
    empty = Geo::Config.new(api_key: "", password: "", data_dir: @directory, file: File.join(@directory, "absent"))
    assert_equal input, empty.redact_secrets(input)
  end

  def test_run_metadata_is_redacted_at_the_recording_boundary
    run = @store.diagnostics.start({ "question" => "示例 #{@config.api_key}" }, @config.method(:redact_secrets))
    run.record("plan", { "nested" => [@config.password] })
    run.finish("complete")
    record = @store.diagnostics.read(run.id)
    assert record["complete"]
    assert_includes record.to_json, "示例 [REDACTED]"
    refute_includes record.to_json, @config.api_key
    refute_includes record.to_json, @config.password
  end

  def test_credentials_matching_protocol_keys_do_not_break_business_parsing
    %w[finish_reason evidence_ids].each do |password|
      config = Geo::Config.new(api_key: @config.api_key, password: password, data_dir: @directory, file: File.join(@directory, "absent"))
      assert config.configured?
      client = Geo::DeepSeek.new(config, @store, transport: transport)
      data = Geo::Pipeline.new(client, @store).run("企业分析工具 #{password}") { |*_| }
      assert_equal "complete", data["status"]
      assert_equal ["S1"], data["cited"]
    end
  end

  def test_partially_escaped_json_credentials_are_redacted_after_decoding
    base = transport
    client = Geo::DeepSeek.new(@config, @store, transport: lambda do |path, payload|
      response = base.call(path, payload)
      if path == "/chat/completions" && payload["max_tokens"] == 600
        content = JSON.generate("queries" => ["企业分析工具"], "answer_plan" => @config.password)
        response[1]["choices"][0]["message"]["content"] = content.sub("fixture", '\u0066ixture')
      end
      response
    end)
    data = Geo::Pipeline.new(client, @store).run("企业分析工具") { |*_| }
    assert_equal "complete", data["status"]
    assert_equal "[REDACTED]", data["intent"]["plan"]
    record = @store.diagnostics.read(data["run_id"])
    upstream = record["events"].find { |event| event["event"] == "upstream" }
    decoded = JSON.parse(upstream["data"]["response"]["choices"][0]["message"]["content"])
    assert_equal "[REDACTED]", decoded["answer_plan"]
    legacy = @config.redact_secrets({ "content" => JSON.generate("nested" => @config.password).sub("fixture", '\u0066ixture') })
    assert_equal "[REDACTED]", JSON.parse(legacy["content"])["nested"]
  end

  def test_json_container_passwords_are_redacted_as_whole_values
    ['{"team":"alpha"}', '["fixture-password-123"]'].each do |password|
      config = Geo::Config.new(api_key: @config.api_key, password: password, data_dir: @directory, file: File.join(@directory, "absent"))
      assert config.configured?
      [password, " #{password} ", JSON.generate("payload" => JSON.parse(password)), JSON.generate("payload" => JSON.parse(password), "other" => config.api_key)].each do |echo|
        assert_equal "[REDACTED]", config.redact_secrets({ "echo" => echo })["echo"]
        run = @store.diagnostics.start({ "question" => echo }, config.method(:redact_secrets))
        run.finish("complete")
        assert_equal "[REDACTED]", @store.diagnostics.read(run.id)["events"].first["data"]["question"]
      end
      encoded = JSON.generate("answer_plan" => password)
      client = Geo::DeepSeek.new(config, @store, transport: ->(*) { [200, { "choices" => [{ "finish_reason" => "stop", "message" => { "content" => encoded } }], "usage" => { "prompt_tokens" => 5, "completion_tokens" => 5 } }] })
      assert_equal "[REDACTED]", client.json("plan", "question", 600)["answer_plan"]
      run = @store.diagnostics.start({ "question" => password }, config.method(:redact_secrets))
      run.finish("complete")
      assert_equal "[REDACTED]", @store.diagnostics.read(run.id)["events"].first["data"]["question"]
      legacy = config.redact_secrets({ "response" => encoded })
      assert_equal "[REDACTED]", JSON.parse(legacy["response"])["answer_plan"]
    end
  end
end
