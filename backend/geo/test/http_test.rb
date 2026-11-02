# frozen_string_literal: true

require_relative "core_test"
require_relative "../lib/app"

class GeoHTTPTest < Minitest::Test
  include GeoFixtures
  def setup
    super
    @app = Geo::App.new(@config, @store, transport: transport)
    @server = WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1", AccessLog: [], Logger: WEBrick::Log.new(File::NULL), ServerType: Thread)
    @server.mount("/", Geo::Servlet, @app)
    @thread = Thread.new { @server.start }
    @port = @server.listeners[0].addr[1]
  end

  def teardown
    @server.shutdown
    @thread.join
    super
  end

  def http(method, path, body: nil, cookie: nil, origin: nil)
    uri = URI("http://127.0.0.1:#{@port}#{path}")
    request = Net::HTTP.const_get(method).new(uri)
    request["Content-Type"] = "application/json"
    request["Cookie"] = cookie if cookie
    request["Origin"] = origin if origin
    request.body = JSON.generate(body) unless body.nil?
    Net::HTTP.new(uri.host, uri.port, nil).start { |connection| connection.request(request) }
  end

  def login
    response = http("Post", "/geo/api/session", body: { password: "fixture-password-123" })
    assert_equal "200", response.code
    response["Set-Cookie"].split(";").first
  end

  def test_unauthenticated_paid_requests_are_blocked
    response = http("Post", "/geo/api/search", body: { question: "数据分析工具怎么选" })
    assert_equal "401", response.code
    assert_equal 0, @calls.length
  end

  def test_login_streaming_and_budget_status_work_end_to_end
    cookie = login
    response = http("Post", "/geo/api/search", body: { question: "企业如何选择数据分析工具" }, cookie: cookie)
    assert_equal "200", response.code
    assert_includes response["Content-Type"], "text/event-stream"
    blocks = response.body.split("\n\n")
    final = blocks.find { |block| block.start_with?("event: result\n") }
    refute_nil final, response.body
    data = JSON.parse(final.split("data: ", 2)[1])
    assert data["live"]
    assert_equal ["S1"], data["cited"]
    refute response.body.include?("fixture-password-123")
    status = JSON.parse(http("Get", "/geo/api/status", cookie: cookie).body)
    assert status["authenticated"]
    assert_operator status["budget"]["used_cny"], :>, 0
  end

  def test_cross_origin_requests_and_wrong_password_are_rejected
    response = http("Post", "/geo/api/session", body: { password: "fixture-password-123" }, origin: "https://untrusted.example")
    assert_equal "403", response.code
    response = http("Post", "/geo/api/session", body: { password: "wrong" })
    assert_equal "401", response.code
  end

  def test_weights_are_validated_before_streaming_and_preserved_in_results
    cookie = login
    bad = http("Post", "/geo/api/search", body: {question:"企业工具",weights:{rel:50}},cookie:cookie)
    assert_equal "400", bad.code
    assert_equal "invalid_weights", JSON.parse(bad.body)["error"]["code"]
    assert_empty @calls
    weights = {"rel"=>50,"auth"=>0,"fresh"=>0,"struct"=>0,"gain"=>0,"cons"=>0}
    response = http("Post", "/geo/api/search", body:{question:"企业工具",weights:weights,ranking_mode:"teaching"},cookie:cookie)
    block = response.body.split("\n\n").find{|part|part.start_with?("event: result\n")}
    refute_nil block, response.body
    assert_equal weights, JSON.parse(block.split("data: ",2)[1])["ranking"]["weights"]
  end

  def test_diagnostic_download_requires_a_session_and_never_exposes_credentials
    assert_equal "401", http("Get", "/geo/api/runs/" + "a" * 32).code
    cookie = login
    response = http("Post", "/geo/api/search", body: { question: "企业分析工具" }, cookie: cookie)
    block = response.body.split("\n\n").find { |part| part.start_with?("event: result\n") }
    data = JSON.parse(block.split("data: ", 2)[1])
    assert_equal "api", data["ranking"]["mode"]
    download = http("Get", "/geo/api/runs/#{data['run_id']}", cookie: cookie)
    assert_equal "200", download.code
    assert_includes download["Content-Disposition"], "attachment"
    assert JSON.parse(download.body)["complete"]
    refute_includes download.body, @config.api_key
    refute_includes download.body, "fixture-password-123"
    assert_equal "404", http("Get", "/geo/api/runs/" + "f" * 32, cookie: cookie).code
    assert_equal "400", http("Get", "/geo/api/runs/not-a-run", cookie: cookie).code
  end

  def test_failed_run_exposes_its_record_id_without_a_paid_retry
    @app.instance_variable_set(:@transport, transport(invalid_citation: true))
    cookie = login
    response = http("Post", "/geo/api/search", body: { question: "企业分析工具" }, cookie: cookie)
    block = response.body.split("\n\n").find { |part| part.start_with?("event: error\n") }
    error = JSON.parse(block.split("data: ", 2)[1])
    assert_equal "invalid_citation", error["code"]
    assert_match(/\A[a-f0-9]{32}\z/, error["run_id"])
    record = JSON.parse(http("Get", "/geo/api/runs/#{error['run_id']}", cookie: cookie).body)
    assert record["events"].any? { |event| event["event"] == "error" && event["data"]["code"] == "invalid_citation" }
    assert_equal 2, @calls.count { |path, _| path == "/chat/completions" }
  end

  def test_static_routes_cannot_read_credentials_or_backend_files
    %w[/backend/geo/lib/config.rb /.env /geo/../../backend/geo/server.rb /credentials.json].each do |path|
      assert_includes ["400", "404"], http("Get", path).code
    end
    assert_equal "200", http("Get", "/geo/").code
  end

  def test_sessions_use_http_only_cookies_and_logout_revokes_access
    response = http("Post", "/geo/api/session", body: { password: "fixture-password-123" })
    assert_includes response["Set-Cookie"], "HttpOnly"
    assert_includes response["Set-Cookie"], "SameSite=Strict"
    cookie = response["Set-Cookie"].split(";").first
    assert_equal "200", http("Delete", "/geo/api/session", cookie: cookie).code
    assert_equal "401", http("Post", "/geo/api/search", body: { question: "测试" }, cookie: cookie).code
  end

  def test_unsent_headers_do_not_claim_a_streaming_slot
    token = @store.session_create
    2.times do
      request = WEBrick::HTTPRequest.new(WEBrick::Config::HTTP)
      request.parse(StringIO.new("POST /geo/api/search HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nCookie: #{Geo::App::COOKIE}=#{token}\r\nContent-Length: 19\r\n\r\n{\"question\":\"test\"}"))
      response = WEBrick::HTTPResponse.new(WEBrick::Config::HTTP)
      @app.call(request, response)
      assert response.body.respond_to?(:call)
      # A disconnect before send_body never invokes this proc.
    end
    assert_equal 0, @app.instance_variable_get(:@active)
    response = http("Post", "/geo/api/search", body: { question: "测试连接恢复" }, cookie: "#{Geo::App::COOKIE}=#{token}")
    assert_includes response.body, "event: result"
    assert_equal 0, @app.instance_variable_get(:@active)
  end

  def test_trusted_proxy_supplies_separate_validated_client_addresses
    request = Struct.new(:headers, :peer) do
      def [](name); headers[name]; end
      def peeraddr; [nil, nil, nil, peer]; end
    end
    previous = ENV["APP_ENV"]
    ENV["APP_ENV"] = "production"
    assert_equal "203.0.113.1", @app.client_ip(request.new({ "x-real-ip" => "203.0.113.1" }, "172.18.0.2"))
    assert_equal "203.0.113.2", @app.client_ip(request.new({ "x-real-ip" => "203.0.113.2" }, "172.18.0.2"))
    assert_equal "172.18.0.2", @app.client_ip(request.new({ "x-real-ip" => "invalid" }, "172.18.0.2"))
    assert_equal "198.51.100.1", @app.client_ip(request.new({ "x-real-ip" => "203.0.113.1" }, "198.51.100.1"))
  ensure
    ENV["APP_ENV"] = previous
  end
end
