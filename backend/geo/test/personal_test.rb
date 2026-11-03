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
    assert_operator Time.parse(x['diagnostics']['expires_at']), :<=, Time.now+30*86400
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
    registry.create(KEY_A,'fixture')
    assert_nil registry.find(tokens[0])
    tokens[0]=registry.create(KEY_A,'fixture')[0]
    replacement,_=registry.create(KEY_B,'fixture',replace:tokens[3])
    assert_nil registry.find(tokens[3])
    assert registry.find(replacement)
    tokens[3]=replacement
    tokens[0]=registry.create(KEY_A,'other-fixture')[0]
    entry=registry.find(tokens[0])
    big='中'*400_000
    3.times{|i|entry.store.cache_put(i.to_s,{'data'=>big})}
    assert_nil entry.store.cache_get('0')
    assert entry.store.cache_get('2')
    registry.use(tokens[0]) do |active|
      now+=Geo::PersonalSessions::TTL+1
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
      now+=Geo::PersonalSessions::TTL+1
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
  def remembered_connect(key=KEY_A, cookie: nil)
    r=http('Post','/geo/api/personal-session',body:{api_key:key},cookie:cookie)
    assert_equal '200',r.code,r.body
    fields=r.get_fields('set-cookie')
    assert_equal 2,fields.length
    assert fields.all?{|v|v.include?('Max-Age=2592000')&&v.include?('HttpOnly')&&v.include?('SameSite=Strict')}
    combined=fields.map{|v|v.split(';').first}.join('; ')
    refute_includes combined,key
    [combined,JSON.parse(r.body),fields]
  end

  def restart_app
    provider=@app.instance_variable_get(:@transport)
    @app=Geo::App.new(@config,@store,transport:provider)
    @server.mount('/',Geo::Servlet,@app)
  end

  def test_remembered_key_restores_after_restart_with_same_identity_and_usage
    cookie,connection=remembered_connect
    result=search_personal(cookie,connection)
    spend=result['budget']['used_cny'];calls=@calls.length
    restart_app
    status=JSON.parse(http('Get','/geo/api/status',cookie:cookie).body)
    assert status['authenticated'];assert status['saved_key']
    assert_equal connection['connection_id'],status['connection_id']
    assert_equal spend,status['budget']['used_cny']
    assert_equal calls,@calls.length
    renewed=search_personal(cookie,status)
    refute renewed['cached'];assert_operator renewed['budget']['used_cny'],:>,spend
    assert_equal 0,@store.budget['used_cny']
    proof=cookie.split('; ').find{|v|v.start_with?('geo_personal_key=')}
    assert JSON.parse(http('Get','/geo/api/status',cookie:proof).body)['authenticated']
  end

  def test_clear_remembered_key_denies_old_cookies_after_restart
    cookie,connection=remembered_connect
    search_personal(cookie,connection)
    cleared=http('Delete','/geo/api/personal-session',cookie:cookie)
    assert_equal '200',cleared.code
    assert cleared.get_fields('set-cookie').all?{|v|v.include?('Max-Age=0')}
    restart_app
    status=JSON.parse(http('Get','/geo/api/status',cookie:cookie).body)
    refute status['authenticated'];refute status['saved_key']
    before=@calls.length
    assert_equal '401',http('Post','/geo/api/search',cookie:cookie,body:{question:'企业工具',connection_id:connection['connection_id']}).code
    assert_equal before,@calls.length
    assert_equal '401',http('Post','/geo/api/personal-session/restore',cookie:cookie).code
    assert_equal 0,@store.budget['used_cny']
  end

  def test_remembered_personal_and_team_switching_preserves_correct_payer
    cookie,personal=remembered_connect
    proof=cookie.split('; ').find{|v|v.start_with?('geo_personal_key=')}
    r=http('Post','/geo/api/session',cookie:cookie,body:{password:'fixture-password-123'})
    team_cookie=r.get_fields('set-cookie').find{|v|v.start_with?('geo_session=')}.split(';').first
    both=team_cookie+'; '+proof
    status=JSON.parse(http('Get','/geo/api/status',cookie:both).body)
    assert_equal 'team',status['access_mode'];assert status['saved_key']
    restored=http('Post','/geo/api/personal-session/restore',cookie:both)
    assert_equal '200',restored.code
    assert_equal personal['connection_id'],JSON.parse(restored.body)['connection_id']
    # A fresh team login remains active when only the saved personal Key is cleared.
    team=login
    clear=http('Delete','/geo/api/personal-session',cookie:team+'; '+proof)
    assert_equal '200',clear.code
    refute clear.get_fields('set-cookie').any?{|v|v.start_with?('geo_session=')}
    assert JSON.parse(http('Get','/geo/api/status',cookie:team).body)['authenticated']
    assert_equal '200',http('Delete','/geo/api/personal-session',cookie:team).code
    assert JSON.parse(http('Get','/geo/api/status',cookie:team).body)['authenticated']
  end

  def test_cipher_authentication_expiry_and_private_secret_survive_reload
    now=1_800_000_000
    vault=Geo::BrowserCredentials.new(@directory,clock:->{now})
    encoded=vault.seal(KEY_A,'a'*64,now+30*86400)
    assert_equal KEY_A,vault.open(encoded)['key']
    reloaded=Geo::BrowserCredentials.new(@directory,clock:->{now})
    assert_equal KEY_A,reloaded.open(encoded)['key']
    tampered=encoded.dup;tampered[20]=tampered[20]=='a'?'b':'a'
    assert_nil reloaded.open(tampered)
    now+=30*86400+1;assert_nil reloaded.open(encoded)
    file=File.join(@directory,'personal-browser.key')
    assert_equal 0600,File.stat(file).mode&0777
    assert_equal 32,File.size(file)
    refute_includes File.binread(file),KEY_A
  end

  def test_failed_explicit_restore_preserves_the_team_session
    cookie,_=remembered_connect
    proof=cookie.split('; ').find{|v|v.start_with?('geo_personal_key=')}
    r=http('Post','/geo/api/session',cookie:cookie,body:{password:'fixture-password-123'})
    team=r.get_fields('set-cookie').first.split(';').first
    registry=@app.instance_variable_get(:@personal)
    tokens=4.times.map{registry.create(KEY_B,'127.0.0.1')[0]}
    nest=lambda do |i|
      if i==tokens.length
        assert_equal '429',http('Post','/geo/api/personal-session/restore',cookie:team+'; '+proof).code
        assert JSON.parse(http('Get','/geo/api/status',cookie:team).body)['authenticated']
      else
        registry.use(tokens[i],exclusive:false){nest.call(i+1)}
      end
    end
    nest.call(0)
  end

  def test_persistent_personal_quota_cannot_reset_when_memory_context_is_recreated
    cookie,connection=remembered_connect
    token=cookie.split('; ').first.split('=',2)[1]
    ledger=Geo::Store::PersonalLedger.new(@store,token,connection['expires_at'],5_000_000)
    id=ledger.reserve('fixture',4_990_000);ledger.settle(id,4_990_000)
    restart_app
    status=JSON.parse(http('Get','/geo/api/status',cookie:cookie).body)
    assert_in_delta 4.99,status['budget']['used_cny'],0.000001
    assert_equal 'budget_exhausted',assert_raises(Geo::Error){ledger.reserve('fixture',20_000)}.code
    assert_equal 0,@store.budget['used_cny']
  end

  def test_clear_during_key_validation_blocks_the_pending_replacement
    thread=release=nil
    [true,false].each do |with_proof|
      cookie,_=remembered_connect
      cookie=cookie.split('; ').first unless with_proof
      entered,release=Queue.new,Queue.new
      provider=@app.instance_variable_get(:@transport)
      @app.instance_variable_set(:@transport,lambda do |path,payload|
        if path=='/user/balance'
          entered << true;release.pop
        end
        provider.call(path,payload)
      end)
      thread=Thread.new{http('Post','/geo/api/personal-session',cookie:cookie,body:{api_key:KEY_B})}
      Timeout.timeout(5){entered.pop}
      assert_equal '200',http('Delete','/geo/api/personal-session',cookie:cookie).code
      release << true
      changed=thread.value
      assert_equal '409',changed.code
      assert_equal 'connection_changed',JSON.parse(changed.body)['error']['code']
      refute changed['Set-Cookie']
      refute JSON.parse(http('Get','/geo/api/status',cookie:cookie).body)['authenticated']
      assert_equal 0,@store.budget['used_cny']
      @app.instance_variable_set(:@transport,provider)
    end
  ensure
    release << true if thread&.alive?
    thread&.join
  end

  def test_two_app_instances_cannot_both_replace_the_same_saved_key
    cookie,_=remembered_connect
    entered,release=Queue.new,Queue.new
    provider=@app.instance_variable_get(:@transport)
    @app.instance_variable_set(:@transport,lambda do |path,payload|
      if path=='/user/balance'
        entered << true;release.pop
      end
      provider.call(path,payload)
    end)
    first=Thread.new{http('Post','/geo/api/personal-session',cookie:cookie,body:{api_key:KEY_B})}
    Timeout.timeout(5){entered.pop}
    original=@app
    restart_app
    second=Thread.new{http('Post','/geo/api/personal-session',cookie:cookie,body:{api_key:KEY_A})}
    Timeout.timeout(5){entered.pop}
    2.times{release << true}
    responses=[first.value,second.value]
    assert_equal ['200','409'],responses.map(&:code).sort
    winner=responses.find{|r|r.code=='200'}
    refute responses.find{|r|r.code=='409'}['Set-Cookie']
    proof=winner.get_fields('set-cookie').map{|v|v.split(';').first}.join('; ')
    expected=JSON.parse(winner.body)['connection_id']
    [@app,original].each do |app|
      @server.mount('/',Geo::Servlet,app)
      state=JSON.parse(http('Get','/geo/api/status',cookie:proof).body)
      assert state['authenticated'];assert_equal expected,state['connection_id']
      refute JSON.parse(http('Get','/geo/api/status',cookie:cookie).body)['authenticated']
    end
    assert_equal 0,@store.budget['used_cny']
  ensure
    2.times{release << true} if release
    first&.join;second&.join
  end

  def test_failed_cookie_encryption_preserves_the_saved_connection
    cookie,connection=remembered_connect
    @app.instance_variable_get(:@browser_keys).define_singleton_method(:seal){|*_|raise OpenSSL::Cipher::CipherError,'fixture failure'}
    failed=http('Post','/geo/api/personal-session',cookie:cookie,body:{api_key:KEY_B})
    assert_equal '500',failed.code
    refute failed['Set-Cookie']
    status=JSON.parse(http('Get','/geo/api/status',cookie:cookie).body)
    assert status['saved_key'];assert status['authenticated']
    assert_equal connection['connection_id'],status['connection_id']
  end

  def test_replacement_capacity_failure_keeps_the_original_grant_restorable
    cookie,connection=remembered_connect
    registry=@app.instance_variable_get(:@personal)
    tokens=4.times.map{registry.create(KEY_B,'127.0.0.1')[0]}
    nest=lambda do |i|
      if i==tokens.length
        failed=http('Post','/geo/api/personal-session',cookie:cookie,body:{api_key:KEY_B})
        assert_equal '429',failed.code
        refute failed['Set-Cookie']
      else
        registry.use(tokens[i],exclusive:false){nest.call(i+1)}
      end
    end
    nest.call(0)
    status=JSON.parse(http('Get','/geo/api/status',cookie:cookie).body)
    assert status['authenticated'];assert_equal connection['connection_id'],status['connection_id']
  end

  def test_clear_revokes_a_committed_replacement_whose_response_arrives_late
    assert_late_replacement_stays_cleared(true)
  end

  def test_legacy_session_clear_revokes_a_replacement_whose_response_arrives_late
    assert_late_replacement_stays_cleared(false)
  end

  def assert_late_replacement_stays_cleared(with_proof)
    cookie,_=remembered_connect
    cookie=cookie.split('; ').first unless with_proof
    prepared,release=Queue.new,Queue.new
    original=@app.method(:json)
    @app.define_singleton_method(:json) do |res,data,status=200|
      original.call(res,data,status)
      if data['access_mode']=='personal' && data['authenticated'] && !data['version']
        prepared << true;release.pop
      end
    end
    pending=Thread.new{http('Post','/geo/api/personal-session',cookie:cookie,body:{api_key:KEY_B})}
    Timeout.timeout(5){prepared.pop}
    assert_equal '200',http('Delete','/geo/api/personal-session',cookie:cookie).code
    release << true
    late=pending.value
    assert_equal '200',late.code
    late_cookie=late.get_fields('set-cookie').map{|v|v.split(';').first}.join('; ')
    late_connection=JSON.parse(late.body)
    restart_app
    state=http('Get','/geo/api/status',cookie:late_cookie)
    refute JSON.parse(state.body)['authenticated']
    refute JSON.parse(state.body)['saved_key']
    refute state['Set-Cookie']
    before=@calls.length
    assert_equal '401',http('Post','/geo/api/search',cookie:late_cookie,body:{question:'企业工具',connection_id:late_connection['connection_id']}).code
    assert_equal before,@calls.length
    fresh,connection=remembered_connect(KEY_A,cookie:late_cookie)
    assert_equal '200',http('Delete','/geo/api/personal-session',cookie:cookie).code
    current=JSON.parse(http('Get','/geo/api/status',cookie:fresh).body)
    assert current['authenticated'];assert_equal connection['connection_id'],current['connection_id']
  ensure
    release << true if pending&.alive?
    pending&.join
  end

  def test_clearing_an_old_saved_key_revokes_its_replacement_chain_and_preserves_team_login
    old,_=remembered_connect
    second,_=remembered_connect(KEY_B,cookie:old)
    current,_=remembered_connect(KEY_A,cookie:second)
    @store.close
    @store=Geo::Store.new(@directory)
    restart_app
    assert_equal '200',http('Delete','/geo/api/personal-session',cookie:old).code
    [old,second,current].each do |value|
      status=JSON.parse(http('Get','/geo/api/status',cookie:value).body)
      refute status['authenticated'];refute status['saved_key']
    end
    team=login
    proof=current.split('; ').find{|v|v.start_with?('geo_personal_key=')}
    status=http('Get','/geo/api/status',cookie:team+'; '+proof)
    assert_equal 'team',JSON.parse(status.body)['access_mode']
    refute status['Set-Cookie']
    assert JSON.parse(http('Get','/geo/api/status',cookie:team).body)['authenticated']
  end

  def test_successor_remains_revoked_through_its_own_later_expiry
    now=Time.now.to_i
    parent,child='a'*64,'b'*64
    parent_expires,child_expires=now+100,now+200
    @store.replace_personal(parent,parent_expires,child,child_expires){true}
    ledger=Geo::Store::PersonalLedger.new(@store,child,child_expires,5_000_000)
    reservation=ledger.reserve('fixture',5000)
    owners=@store.revoke_personal(parent,parent_expires)
    assert_includes owners,Digest::SHA256.hexdigest(child)
    Time.stub(:now,Time.at(parent_expires+1)) do
      assert @store.personal_revoked?(child)
      assert_equal 'unauthorized',assert_raises(Geo::Error){ledger.reserve('fixture',5000)}.code
      ledger.settle(reservation,2000)
      assert_in_delta 0.002,ledger.budget['used_cny'],0.000001
    end
    assert_equal 0,@store.budget['used_cny']
  end

  def test_public_connection_id_cannot_clear_successors_and_legacy_logout_can
    old,connection=remembered_connect
    current,_=remembered_connect(KEY_B,cookie:old)
    public_id='geo_session='+connection['connection_id']
    assert_equal '200',http('Delete','/geo/api/personal-session',cookie:public_id).code
    assert JSON.parse(http('Get','/geo/api/status',cookie:current).body)['authenticated']
    legacy=old.split('; ').first
    assert_equal '200',http('Delete','/geo/api/session',cookie:legacy).code
    refute JSON.parse(http('Get','/geo/api/status',cookie:current).body)['authenticated']
  end

end
