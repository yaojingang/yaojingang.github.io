/* Browser checks against the actual app with fake DeepSeek responses. */
const {chromium}=require('playwright');
const {spawn}=require('node:child_process');
const path=require('node:path'),fs=require('node:fs'),os=require('node:os'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../../..'),artifacts=fs.mkdtempSync(path.join(os.tmpdir(),'geo-personal-ui-'));
const key='sk-browser-fixture-12345678901234567890';
const ruby=String.raw`
require 'tmpdir'
require File.expand_path('backend/geo/lib/app',Dir.pwd)
STDOUT.sync=true
Dir.mktmpdir('geo-personal-http-') do |directory|
 config=Geo::Config.new(api_key:'sk-team-fixture-1234567890123456',password:'fixture-password-123',data_dir:directory,file:File.join(directory,'none'))
 store=Geo::Store.new(directory)
 provider=lambda do |route,payload|
  case route
  when '/user/balance' then [200,{'is_available'=>true}]
  when '/v1/tools/search' then [200,{'results'=>[{'url'=>'https://example.org/guide','title'=>'企业分析工具指南','site_name'=>'测试资料','rerank_score'=>2.5,'authority'=>3,'content'=>'企业数据分析工具需要结合团队协作需求、数据规模和接入成本选择。'}]}]
  when '/chat/completions'
   value=if payload['max_tokens']==600
    {'queries'=>['企业分析工具']}
   else
    ids=JSON.parse(payload['messages'][1]['content'])['evidence'].map{|e|e['id']}
    {'paragraphs'=>[{'text'=>'企业应结合数据规模和协作需求，比较工具的接入与维护成本。','evidence_ids'=>ids}]}
   end
   [200,{'choices'=>[{'finish_reason'=>'stop','message'=>{'content'=>JSON.generate(value)}}],'usage'=>{'prompt_tokens'=>100,'completion_tokens'=>80}}]
  else raise 'Unexpected fake endpoint'
  end
 end
 app=Geo::App.new(config,store,transport:provider)
 server=WEBrick::HTTPServer.new(Port:0,BindAddress:'127.0.0.1',AccessLog:[],Logger:WEBrick::Log.new(File::NULL))
 server.mount('/',Geo::Servlet,app)
 Thread.new{STDIN.read;server.shutdown}
 puts server.listeners[0].addr[1]
 begin server.start;ensure store.close;end
end
`;
const child=spawn('ruby',['-e',ruby],{cwd:root,stdio:['pipe','pipe','pipe']});let serverErrors='';child.stderr.on('data',v=>serverErrors+=v);
(async()=>{
 let browser;
 try{
  const port=await new Promise((resolve,reject)=>{child.stdout.once('data',b=>resolve(Number(String(b).trim())));child.once('exit',code=>reject(new Error('Fixture exited '+code+': '+serverErrors)));});assert(port>0);
  const base='http://127.0.0.1:'+port;
  const nodes=new Map();const node=id=>{if(!nodes.has(id))nodes.set(id,{hidden:id==='connected',value:'',textContent:'',type:'password',disabled:false,onclick:null,onsubmit:null,setAttribute(){},removeAttribute(){},addEventListener(){},focus(){},querySelector:s=>node(id+s)});return nodes.get(id);};
  let statusResolve,verifyResolve;
  const initial=new Promise(r=>statusResolve=r),validation=new Promise(r=>verifyResolve=r);
  const sandbox={document:{getElementById:node},window:{addEventListener(){},location:{replace(){throw Error('Unexpected successful validation');}}},sessionStorage:{removeItem(){},setItem(){}},fetch:url=>url.endsWith('/status')?initial:validation};
  require('node:vm').runInNewContext(fs.readFileSync(path.join(root,'geo/connect.js'),'utf8'),sandbox);
  node('api-key').value=key;const submission=node('key-form').onsubmit({preventDefault(){}});
  statusResolve({ok:true,json:async()=>({authenticated:true,access_mode:'personal'})});await new Promise(r=>setImmediate(r));
  verifyResolve({ok:false,json:async()=>({error:{message:'新 Key 无效'}})});await submission;
  assert.equal(node('key-form').hidden,false,'A late status response must keep a new Key failure visible');assert.equal(node('connected').hidden,true);assert.equal(node('key-error').textContent,'新 Key 无效');

  browser=await chromium.launch({headless:true});const ctx=await browser.newContext({viewport:{width:1440,height:1000},reducedMotion:'reduce'}),page=await ctx.newPage(),errors=[],requests=[];
  page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>requests.push(r.url()));
  await page.goto(base+'/geo/');await page.getByRole('link',{name:'使用自己的 DeepSeek Key'}).click();
  await page.locator('#api-key').waitFor();
  assert.equal(await page.locator('#api-key').getAttribute('type'),'password');assert.equal(await page.locator('#api-key').getAttribute('autocomplete'),'off');
  assert.equal(await page.getByRole('link',{name:'打开 API Keys ↗'}).getAttribute('href'),'https://platform.deepseek.com/api_keys');
  assert(!requests.some(u=>u.includes('baidu')||u.includes('google-analytics')));
  for(const scheme of['light','dark']){await page.emulateMedia({colorScheme:scheme});for(const width of[1440,768,640,390,320]){await page.setViewportSize({width,height:1000});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));if(width===1440||width===390)await page.screenshot({path:path.join(artifacts,'connect-'+scheme+'-'+width+'.png'),fullPage:true});}}
  await page.emulateMedia({colorScheme:'light'});await page.setViewportSize({width:1440,height:1000});
  await page.locator('#api-key').fill(key);await page.getByRole('button',{name:'显示 API Key',exact:true}).click();assert.equal(await page.locator('#api-key').getAttribute('type'),'text');
  await page.getByRole('button',{name:'隐藏 API Key',exact:true}).click();assert.equal(await page.locator('#api-key').getAttribute('type'),'password');
  await page.route('**/geo/api/personal-session',r=>r.fulfill({status:401,contentType:'application/json',body:JSON.stringify({error:{code:'invalid_key',message:'DeepSeek Key 无效，请核对后重试。'}})}));
  await page.locator('#connect').click();await page.locator('#key-error').filter({hasText:'无效'}).waitFor();assert.equal(await page.locator('#api-key').inputValue(),'');assert(await page.locator('#connect').isEnabled());
  await page.unroute('**/geo/api/personal-session');await page.locator('#api-key').fill(key);await page.locator('#connect').click();await page.waitForURL('**/geo/');await page.waitForFunction(()=>GeoLive.active);
  assert.equal(await page.locator('.brand small').innerText(),'个人版');assert((await page.locator('#live-status').innerText()).includes('个人 Key'));assert((await page.locator('#live-status').innerText()).includes('5.000'));
  assert(!(await page.evaluate(()=>JSON.stringify({...sessionStorage,...localStorage}))).includes(key));
  const firstId=await page.evaluate(()=>GeoLive.connectionId);
  await page.getByRole('link',{name:'管理连接',exact:true}).click();await page.locator('#connected').waitFor({state:'visible'});
  await page.locator('#replace-key').click();await page.locator('#api-key').fill(key);
  await page.route('**/geo/api/personal-session',r=>r.fulfill({status:401,contentType:'application/json',body:JSON.stringify({error:{message:'新 Key 无效'}})}));
  await page.locator('#connect').click();await page.locator('#key-error').filter({hasText:'无效'}).waitFor();
  const retained=await(await ctx.request.get(base+'/geo/api/status')).json();assert.equal(retained.connection_id,firstId);
  await page.unroute('**/geo/api/personal-session');await page.locator('#api-key').fill('sk-browser-second-98765432109876543210');await page.locator('#connect').click();await page.waitForURL('**/geo/');await page.waitForFunction(()=>GeoLive.active);assert.notEqual(await page.evaluate(()=>GeoLive.connectionId),firstId);

  await page.locator('#q-home').fill('企业分析工具');await page.locator('#f-home .send').click();await page.locator('#answer .seg').first().waitFor();
  assert((await page.locator('#r-banner').innerText()).includes('个人连接保守计费'));
  await page.locator('#xswitch').click();await page.locator('#live-pipe-go').click();assert.equal(await page.locator('#rail .st').count(),6);
  await page.screenshot({path:path.join(artifacts,'personal-process.png'),fullPage:true});
  const pin=await page.evaluate(()=>GeoLive.connectionId);assert(pin&&pin.length===64);
  const switchResponse=await ctx.request.post(base+'/geo/api/session',{data:{password:'fixture-password-123'},headers:{Origin:base}});assert(switchResponse.ok());
  const denied=await ctx.request.post(base+'/geo/api/search',{data:{question:'企业分析工具',connection_id:pin},headers:{Origin:base}});assert.equal(denied.status(),409);
  const teamStatus=await(await ctx.request.get(base+'/geo/api/status')).json();assert.equal(teamStatus.budget.used_cny,0);
  await page.goto(base+'/geo/');await page.waitForFunction(()=>GeoLive.active);assert.equal(await page.locator('.brand small').innerText(),'内测版');
  await ctx.request.delete(base+'/geo/api/session',{headers:{Origin:base}});
  await page.evaluate(()=>{sessionStorage.setItem('geo-provider','personal');sessionStorage.setItem('geo-mode','live');});await page.reload();await page.waitForFunction(()=>window.GeoLive&&!GeoLive.active);
  await page.getByRole('button',{name:'实时内测',exact:true}).click();await page.locator('.live-dialog').waitFor({state:'visible'});assert(await page.locator('.live-dialog').isVisible());
  await page.locator('#live-close').click();await page.getByRole('link',{name:'使用自己的 DeepSeek Key'}).click();await page.locator('#api-key').fill(key);await page.locator('#connect').click();await page.waitForURL('**/geo/');await page.waitForFunction(()=>GeoLive.active);
  await page.getByRole('button',{name:'断开 Key',exact:true}).click();await page.waitForFunction(()=>!GeoLive.active);assert.equal(await page.evaluate(()=>sessionStorage.getItem('geo-provider')),null);
  await page.getByRole('button',{name:'实时内测',exact:true}).click();await page.locator('.live-dialog').waitFor({state:'visible'});assert(await page.locator('.live-dialog').isVisible());
  assert.deepEqual(errors,[]);console.log(JSON.stringify({result:'PASS',widths:[1440,768,640,390,320],modes:['personal','team','expired','disconnected'],artifacts}));
 }finally{if(browser)await browser.close();child.stdin.end();}
})().catch(e=>{console.error(e.stack);process.exitCode=1;});
