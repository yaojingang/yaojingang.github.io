# frozen_string_literal: true
require_relative 'http_test'

class GeoPersonalTest < GeoHTTPTest
  KEY_A = 'sk-personal-A-12345678901234567890'
  KEY_B = 'sk-personal-B-98765432101234567890'

  def setup
    super
    @balance = [200, { 'is_available' => true }]
    base = transport
    @app.instance_variable_set(:@transport, lambda do |path, payload|
      if path == '/user/balance'
        @calls << [path, payload]
        @balance
      else
        base.call(path, payload)
      end
    end)
  end

  def connect(key = KEY_A, cookie: nil)
    r = http('Post', '/geo/api/personal-session', body: {api_key:key}, cookie:cookie)
    assert_equal '200', r.code, r.body
    [r['Set-Cookie'].split(';').first, JSON.parse(r.body)]
  end

  def search_personal(cookie, connection, question = '企业分析工具')
    r = http('Post', '/geo/api/search', cookie:cookie, body:{question:question, connection_id:connection['connection_id']})
    block = r.body.split("\n\n").find { |part| part.start_with?("event: result\n") }
    assert block, r.body
    JSON.parse(block.split('data: ',2)[1])
  end

  def test_personal_search_cache_budget_and_records_are_isolated
    a,ca = connect
    b,cb = connect(KEY_B)
    x = search_personal(a,ca)
    y = search_personal(b,cb)
    assert_equal 'personal', x['access_mode']
    assert_equal 5, x['budget']['limit_cny']
    assert_operator x['budget']['used_cny'], :>, 0
    assert_equal 0, @store.budget['used_cny']
    refute x['cached'];refute y['cached']
    refute_equal x['run_id'],y['run_id']
    assert_equal 'memory', x['diagnostics']['storage']
    assert_operator Time.parse(x['diagnostics']['expires_at']), :<=, Time.now+3600
    calls=@calls.length
    cached=search_personal(a,ca)
    assert cached['cached'];assert_equal calls,@calls.length
    assert_equal '200',http('Get',"/geo/api/runs/#{x['run_id']}",cookie:a).code
    assert_equal '404',http('Get',"/geo/api/runs/#{x['run_id']}",cookie:b).code
    team=login
    assert_equal '404',http('Get',"/geo/api/runs/#{x['run_id']}",cookie:team).code
    Dir.glob(File.join(@directory,'**','*')).select{|p|File.file?(p)}.each do |path|
      bytes=File.binread(path);refute_includes bytes,KEY_A;refute_includes bytes,KEY_B
    end
    assert_equal '200',http('Delete','/geo/api/session',cookie:a).code
    assert_equal '401',http('Get',"/geo/api/runs/#{x['run_id']}",cookie:a).code
  end

  def test_validation_rejects_bad_key_empty_balance_and_network_errors_without_team_spend
    r=http('Post','/geo/api/personal-session',body:{api_key:"sk-secret\r\nBad: injected"})
    assert_equal '400',r.code;assert_empty @calls
    [[401,{},'401'],[200,{'is_available'=>false},'402'],[500,{},'502'],[200,{},'502']].each do |status,data,expected|
      @balance=[status,data]
      r=http('Post','/geo/api/personal-session',body:{api_key:KEY_A})
      assert_equal expected,r.code;refute r['Set-Cookie'];refute_includes r.body,KEY_A
    end
    assert_equal 0,@store.budget['used_cny']
    assert_equal 0,@calls.count{|path,_|path=='/chat/completions'}
  end

  def test_connection_identity_prevents_cross_tab_charging_and_failed_replace_keeps_old
    a,ca=connect
    b,cb=connect(KEY_B,cookie:a)
    assert_equal '401',http('Post','/geo/api/search',cookie:a,body:{question:'企业分析工具',connection_id:ca['connection_id']}).code
    before=@calls.length
    [ca['connection_id'],nil].each do |id|
      r=http('Post','/geo/api/search',cookie:b,body:{question:'企业分析工具',connection_id:id})
      assert_equal '409',r.code
      assert_equal 'connection_changed',JSON.parse(r.body)['error']['code']
    end
    assert_equal before,@calls.length
    @balance=[401,{}]
    r=http('Post','/geo/api/personal-session',cookie:b,body:{api_key:KEY_A})
    assert_equal '401',r.code
    assert JSON.parse(http('Get','/geo/api/status',cookie:b).body)['authenticated']
    refute_includes cb.to_json,KEY_B
    team=login
    r=http('Post','/geo/api/search',cookie:team,body:{question:'企业分析工具',connection_id:cb['connection_id']})
    assert_equal '409',r.code
    assert_equal 0,@store.budget['used_cny']
  end

  def test_disconnect_stops_later_paid_calls_and_settles_started_call
    cookie,connection=connect
    entered,release=Queue.new,Queue.new
    base=transport
    @app.instance_variable_set(:@transport,lambda do |path,payload|
      if path=='/chat/completions' && payload['max_tokens']==600
        entered << true;release.pop
      end
      base.call(path,payload)
    end)
    response=nil
    thread=Thread.new{response=http('Post','/geo/api/search',cookie:cookie,body:{question:'企业分析工具',connection_id:connection['connection_id']})}
    entered.pop
    assert_equal '200',http('Delete','/geo/api/session',cookie:cookie).code
    release << true;thread.join
    assert_includes response.body,'unauthorized'
    refute_includes response.body,'event: result'
    assert_equal 1,@calls.count{|path,_|path=='/chat/completions'}
    assert_equal 0,@calls.count{|path,_|path=='/v1/tools/search'}
    assert_equal 0,@store.budget['used_cny']
  ensure
    release << true if thread&.alive?
    thread&.join
  end

  def test_personal_page_is_separate_from_analytics_and_has_strict_csp
    r=http('Get','/geo/api/connect')
    assert_equal '200',r.code
    assert_includes r['Content-Type'],'text/html'
    assert_includes r['Content-Security-Policy'],"frame-ancestors 'none'"
    assert_includes r['Content-Security-Policy'],"script-src 'self'"
    refute_includes r.body,'baidu';refute_includes r.body,'{%'
    assert_includes r.body,'https://platform.deepseek.com/api_keys'
    assert_equal '200',http('Get','/geo/connect.js').code
    assert_equal '200',http('Get','/geo/connect.css').code
    r=http('Post','/geo/api/personal-session',body:{api_key:KEY_A},origin:'https://elsewhere.example')
    assert_equal '403',r.code
  end

  def test_registry_expiry_capacity_and_memory_limits
    now=100
    registry=Geo::PersonalSessions.new(clock:->{now})
    tokens=4.times.map{registry.create(KEY_A,'fixture')[0]}
    assert_raises(Geo::Error){registry.create(KEY_A,'fixture')}
    replacement,_=registry.create(KEY_B,'fixture',replace:tokens[3])
    assert_nil registry.find(tokens[3])
    assert registry.find(replacement)
    tokens[3]=replacement
    entry=registry.find(tokens[0])
    big='中'*400_000
    3.times{|i|entry.store.cache_put(i.to_s,{'data'=>big})}
    assert_nil entry.store.cache_get('0')
    assert entry.store.cache_get('2')
    registry.use(tokens[0]) do |active|
      now+=3601
      assert_nil registry.find(tokens[0])
      assert_equal 0,active.store.budget['used_cny']
    end
    assert_nil registry.find(tokens[1])
    assert_equal 4,tokens.length
  end

  def test_expiry_between_paid_calls_blocks_new_reservations
    now=100
    registry=Geo::PersonalSessions.new(clock:->{now})
    token,entry=registry.create(KEY_A,'fixture')
    registry.use(token) do
      authorize=->{raise Geo::Error.new('unauthorized','expired',401) unless registry.find(token)}
      client=Geo::DeepSeek.new(entry.config,entry.store,transport:transport,authorize:authorize)
      client.search('企业工具','企业工具')
      spent=entry.store.budget['used_cny'];calls=@calls.length
      now+=3601
      assert_equal 'unauthorized',assert_raises(Geo::Error){client.search('企业工具','企业工具')}.code
      assert_equal calls,@calls.length
      assert_equal spent,entry.store.budget['used_cny']
    end
  end

  def test_personal_upstream_echo_is_redacted_from_answer_cache_and_diagnostics
    cookie,connection=connect
    base=transport
    @app.instance_variable_set(:@transport,lambda do |path,payload|
      status,data=base.call(path,payload)
      data['results'][0]['content']+=" 回显的密钥为 #{KEY_A}。" if path=='/v1/tools/search'
      [status,data]
    end)
    result=search_personal(cookie,connection)
    refute_includes result.to_json,KEY_A
    record=http('Get',"/geo/api/runs/#{result['run_id']}",cookie:cookie)
    refute_includes record.body,KEY_A
    assert_includes record.body,'[REDACTED]'
    cached=search_personal(cookie,connection)
    assert cached['cached'];refute_includes cached.to_json,KEY_A
  end
end
