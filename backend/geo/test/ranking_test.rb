# frozen_string_literal: true
require_relative "core_test"

class GeoRankingTest < Minitest::Test
  include GeoFixtures

  def test_weights_match_the_teaching_prototype_and_reject_invalid_input_before_billing
    assert_equal({"rel"=>30,"auth"=>20,"fresh"=>15,"struct"=>15,"gain"=>10,"cons"=>10}, Geo::Ranking.weights(nil))
    [[], {}, {"rel"=>-5}, {"rel"=>51}, {"rel"=>"30"}, {"rel"=>0,"auth"=>0,"fresh"=>0,"struct"=>0,"gain"=>0,"cons"=>0}, {"rel"=>30,"extra"=>5}].each do |invalid|
      assert_raises(Geo::Error) { pipeline.run("企业数据分析工具", weights: invalid) { |*_| } }
    end
    assert_empty @calls
  end

  def test_weighted_score_excludes_unknown_dimensions_and_has_a_stable_tie_break
    weights = Geo::Ranking.weights(nil)
    source = {"sig"=>[80,nil,60,90,70,50]}
    assert_in_delta 73.125, Geo::Ranking.score(source, weights), 0.001
    assert_nil Geo::Ranking.score({"sig"=>[nil]*6}, weights)
    only_auth = Geo::Ranking::DEFAULT.transform_values { 0 }.merge("auth"=>50)
    assert_nil Geo::Ranking.score(source, only_auth)
    rows = %w[b a].map{|name|{"url"=>"https://example.org/#{name}","api_score"=>2.5,"sig"=>[80]*6,"eligible"=>true}}
    assert_equal %w[https://example.org/a https://example.org/b], Geo::Ranking.order(rows, weights).map{|s|s["url"]}
  end

  def test_segment_decisions_preserve_rejected_navigation_and_the_actual_selected_text
    base = transport
    provider = lambda do |path,payload|
      status,response = base.call(path,payload)
      if path=="/v1/tools/search"
        response["results"].first["content"] = "首页\n联系我们\n\n企业工具选型应核对数据规模、团队协作需求和接入成本。"
      end
      [status,response]
    end
    data=Geo::Pipeline.new(Geo::DeepSeek.new(@config,@store,transport:provider),@store).run("企业工具选型"){|*_|}
    source=data["sources"].find{|s|s["url"]=="https://example.org/analysis"}
    assert_equal [false,true],source["segments"].map{|s|s["picked"]}
    assert_match(/导航/,source["segments"][0]["reason"])
    chosen=source["segments"].select{|s|s["picked"]}.map{|s|s["text"]}
    assert_equal chosen, data["evidence"].select{|e|e["source_id"]==source["id"]}.map{|e|e["text"]}
  end

  def test_authority_weights_change_the_actual_read_set_and_cannot_admit_low_relevance
    results = 7.times.map do |i|
      {"url"=>"https://s#{i}.example.org/guide", "title"=>"企业分析工具", "site_name"=>"资料#{i}",
       "content"=>"企业数据分析工具需要考虑数据规模、团队协作和接入成本。", "rerank_score"=>i==6 ? 1.2 : 2.9-i*0.1, "authority"=>i==5 || i==6 ? 4 : 1}
    end
    provider = lambda do |path,payload|
      response = transport.call(path,payload)
      path=="/v1/tools/search" ? [200,{"results"=>results}] : response
    end
    flow = Geo::Pipeline.new(Geo::DeepSeek.new(@config,@store,transport:provider),@store)
    rel = {"rel"=>50,"auth"=>0,"fresh"=>0,"struct"=>0,"gain"=>0,"cons"=>0}
    auth = rel.merge("rel"=>0,"auth"=>50)
    first = flow.run("企业分析工具", weights: rel, ranking_mode: "teaching") { |*_| }
    second = flow.run("企业分析工具", weights: auth, ranking_mode: "teaching") { |*_| }
    refute_equal first["sources"].select{|s|s["read"]}.map{|s|s["url"]}, second["sources"].select{|s|s["read"]}.map{|s|s["url"]}
    assert_equal "资料5", second["sources"].find{|s|s["read"]}["site"]
    refute second["sources"].find{|s|s["site"]=="资料6"}["read"]
    assert_equal auth, second["ranking"]["weights"]
    assert second["sources"].all?{|s|s["sig"].length==6 && s["sig_basis"].length==6}
    calls = @calls.length
    cached = flow.run("企业分析工具", weights: auth, ranking_mode: "teaching") { |*_| }
    assert cached["cached"]
    assert_equal calls, @calls.length
    refute first["cached"]
    refute second["cached"]
  end

  def test_future_or_missing_dates_stay_unknown_and_cross_source_matches_need_other_hosts
    rows = [
      {"url"=>"https://same.example/a","date"=>"2099-01-01","authority"=>-1,"api_score"=>2.7,"content"=>"企业数据分析需要结合团队协作需求和数据规模。"},
      {"url"=>"https://same.example/b","date"=>"日期未知","authority"=>2,"api_score"=>2.6,"content"=>"企业数据分析需要结合团队协作需求和数据规模。"}
    ]
    Geo::Ranking.measure(rows, now: Time.utc(2026,11,1))
    assert_nil rows[0]["sig"][1]
    assert_nil rows[0]["sig"][2]
    assert_nil rows[1]["sig"][2]
    assert_nil rows[0]["sig"][5]
    assert_nil rows[1]["sig"][5]
  end

  def test_all_candidates_are_preserved_so_a_new_weight_profile_can_promote_the_twentieth_source
    results = 20.times.map do |i|
      {"url"=>"https://s#{i}.example.org/guide", "site_name"=>"资料#{i}", "title"=>"企业分析工具",
       "content"=>"企业数据分析工具需要考虑数据规模、团队协作和接入成本。", "rerank_score"=>i==19 ? 2.0 : 2.99-i*0.01,"authority"=>i==19 ? 4 : 1}
    end
    searches=0
    provider=lambda do |path,payload|
      response=transport.call(path,payload)
      if path=="/v1/tools/search"
        rows=results.slice(searches%2*10,10);searches+=1;[200,{"results"=>rows}]
      else
        response
      end
    end
    flow=Geo::Pipeline.new(Geo::DeepSeek.new(@config,@store,transport:provider),@store)
    rel={"rel"=>50,"auth"=>0,"fresh"=>0,"struct"=>0,"gain"=>0,"cons"=>0}
    auth=rel.merge("rel"=>0,"auth"=>50)
    first=flow.run("企业分析工具",weights:rel,ranking_mode:"teaching"){|*_|}
    assert_equal 20,first["sources"].length
    preview=Geo::Ranking.order(Marshal.load(Marshal.dump(first["sources"])),auth,mode:"teaching").first(5).map{|s|s["url"]}
    applied=flow.run("企业分析工具",weights:auth,ranking_mode:"teaching"){|*_|}
    assert_equal preview,applied["sources"].select{|s|s["read"]}.map{|s|s["url"]}
    assert_equal "资料19",applied["sources"].first["site"]
  end
end
