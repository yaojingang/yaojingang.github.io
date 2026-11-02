/* Offline browser regression checks against the teaching UI's shared components. */
const {chromium} = require('playwright');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..');
const artifacts = fs.mkdtempSync(path.join(os.tmpdir(), 'geo-ui-check-'));
const text = '根据团队使用场景、数据规模与协作需求选择分析工具，并核对产品原始资料。';
const defaults={rel:30,auth:20,fresh:15,struct:15,gain:10,cons:10}, requests=[];
const sources = [
  {id:'S1',site:'一个名称较长的数据分析研究中心资料库',title:'数据分析工具选型与团队协作指南',url:'https://example.org/analysis',api_score:2.65,authority:3,date:'2026-11-01'},
  {id:'S2',site:'e5b7a5e585b7e69687e6a1a3',title:'产品说明 <img src=x onerror="window.__geoXSS=1">',url:'https://example.net/guide',api_score:2.13,authority:2,date:'2026-10-30'}
].map((s,i)=>({...s,snip:text,tc:'#2d5bff',ic:s.site[0],r0:i,v0:s.api_score,type:'网页正文',read:true,eligible:true,why:'本次回答引用了此来源的选段。',sig:i?[71,100,99,80,50,60]:[88.33,25,99,95,80,80],sig_basis:Array.from({length:6},(_,j)=>'第 '+(j+1)+' 维分数的离线依据。'),weighted_score:i?79.15:76.599,language:'zh-Hans',language_priority:0,language_allowed:true,language_supplement:false,segments:[{text:'首页\n联系我们',index:0,picked:false,basis:'body',term_hits:0,reason:'导航标签，未采用。'},{text,index:1,picked:true,basis:'body',term_hits:3,reason:'完整语句，进入上下文。'}]}));
const evidence = sources.map(s=>({id:s.id+'-P1',source_id:s.id,text:text.repeat(24),basis:'body',term_hits:2}));
const refs = evidence.map(e=>({id:e.source_id,q:e.text,evidence_id:e.id,basis:e.basis}));
const data = {live:true,query:'企业应该怎样选择数据分析工具？',ranking:{weights:defaults,limit:5},intent:{type:'工具选型',ents:['分析工具'],cons:[['使用场景','团队协作']],plan:'先比较场景，再核对接入条件。'},searches:[{query:'企业应该怎样选择数据分析工具？ lang:zh',count:2},{query:'数据分析工具 团队协作 lang:zh',count:2}],sources,evidence,answer:[{t:'p',segs:[{x:text.repeat(4),f:refs}]},{t:'p',segs:[{x:text,f:[refs[0]]}]}],cited:['S1','S2'],trace:Array.from({length:6},(_,stage)=>({stage,message:['保留原始问题，生成搜索词。','实际检索 2 组查询。','按 1.50 分选用线筛选来源。','已记录 2 段正文。','已整理 2 段回答。','引用 2 个来源。'][stage]})),total:4,dedup:2,cached:false,status:'complete',quality:{min_score:1.5,eligible_count:2,read_count:2,language:'zh',preferred_language:'zh-Hans',language_fallback:false},warnings:[],created_at:'2026-11-01T19:00:00+08:00',elapsed_seconds:2.18,budget:{limit_cny:50,used_cny:0.12,remaining_cny:49.88}};
let loggedIn = false, waitingResponse;
const files = {'/geo/':['geo/index.html','text/html'],'/geo/live.js':['geo/live.js','text/javascript'],'/geo/live.css':['geo/live.css','text/css'],'/geo/test-questions.json':['geo/test-questions.json','application/json']};
const json = (res, value, code=200) => {res.writeHead(code, {'Content-Type':'application/json'});res.end(JSON.stringify(value));};
const server = http.createServer(async(req,res)=>{
  const pathname = new URL(req.url,'http://localhost').pathname;
  if(pathname==='/geo/api/status') return json(res,{configured:true,authenticated:loggedIn,budget:data.budget});
  if(pathname==='/geo/api/session'){loggedIn=req.method==='POST';return json(res,{authenticated:loggedIn,budget:data.budget});}
  if(pathname==='/geo/api/search'){
    let body='';for await(const chunk of req) body+=chunk;
    const payload=JSON.parse(body);requests.push(payload);const question=payload.question;
    if(question==='错误状态测试') return json(res,{error:{message:'离线限流测试，请稍后再试。'}},429);
    res.writeHead(200,{'Content-Type':'text/event-stream; charset=utf-8'});
    if(question==='等待检索测试'){waitingResponse=res;res.write('event: step\ndata: {"stage":0,"message":"正在理解问题。"}\n\n');return;}
    const output=structuredClone(data);output.query=question;output.ranking.weights=payload.weights||defaults;
    if(question==='语言补充测试'){output.quality.language_fallback=true;output.sources=output.sources.map((s,i)=>({...s,language:i?'en':'zh-Hant',language_priority:i?2:1,language_supplement:true}));}
    if(question==='数学分析师推荐')Object.assign(output,{status:'insufficient',answer:[],cited:[],evidence:[],quality:{min_score:1.5,eligible_count:0,read_count:0,language:'zh'},sources:output.sources.map(s=>({...s,api_score:1.2,read:false,eligible:false,type:'搜索结果',why:'API 排序分低于本站 1.50 分选用线。'})),diagnostic:'本次没有找到足够相关且内容可用的资料。请补充推荐对象、使用场景或地区，再继续检索。',searches:[{query:'数学分析师推荐 lang:zh',count:2},{query:'数学分析师 推荐 lang:zh',count:2}],trace:output.trace.map(row=>({...row,message:row.stage===3?'没有找到有效选段。':row.stage===4?'资料不足，没有调用回答模型。':row.stage===5?'没有形成引用。':row.message}))});
    const bytes=Buffer.from('event: result\ndata: '+JSON.stringify(output)+'\n\n');
    for(let offset=0;offset<bytes.length;offset+=137)res.write(bytes.subarray(offset,offset+137));
    return res.end();
  }
  if(!files[pathname]){res.writeHead(404);return res.end();}
  const [relative,type]=files[pathname];let body=fs.readFileSync(path.join(root,relative),'utf8');
  if(type==='text/html')body=body.replace(/^---\n[\s\S]*?\n---\n/,'').replace('{% include baidu-analytics.html %}','');
  res.writeHead(200,{'Content-Type':type+'; charset=utf-8'});res.end(body);
});
(async()=>{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const browser=await chromium.launch({headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1000},reducedMotion:'reduce'}), errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  const resize=async width=>{await page.setViewportSize({width,height:1000});await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));};
  await page.goto('http://127.0.0.1:'+server.address().port+'/geo/');
  await page.getByRole('button',{name:'数据分析推荐',exact:true}).click();await page.evaluate(()=>finishThink(false));
  const metrics=()=>page.evaluate(()=>{const source=document.querySelector('#side .src'),style=getComputedStyle(source);return{width:source.getBoundingClientRect().width,padding:style.padding,border:style.borderWidth,radius:style.borderRadius,gap:getComputedStyle(source.parentElement).gap,titleFont:getComputedStyle(source.querySelector('.src-t')).fontSize};});
  const teaching=await metrics();
  await page.getByRole('button',{name:'实时内测',exact:true}).click();
  await page.locator('#live-password').fill('offline-fixture-password');
  await page.getByRole('button',{name:'进入内测',exact:true}).click();await page.waitForFunction(()=>GeoLive.active);
  if(process.env.GEO_LOADING_ONLY){
   await page.evaluate(()=>setXray(true,true));
   page.evaluate(()=>GeoLive.search('等待检索测试')).catch(()=>{});
   await page.locator('#live-cancel').waitFor({state:'visible'});
   const boxes=await page.evaluate(()=>({width:innerWidth,legend:document.querySelector('#legend').getBoundingClientRect().height,progress:document.querySelector('#think').getBoundingClientRect().height}));
   await page.screenshot({path:path.join(artifacts,'loading-desktop.png'),fullPage:true});
   console.log(JSON.stringify({loading:boxes,artifacts}));
   assert.equal(boxes.legend,0,'Empty legend should take no layout space during loading');
   assert.equal(await page.locator('.live-phase').count(),6);assert.equal(await page.locator('.live-phase.cur').count(),1);
   await page.locator('#live-cancel').click();await page.waitForFunction(()=>!state.thinking);
   return;
  }
  await page.evaluate(()=>openProcess(0));
  assert(await page.locator('#home').isVisible());
  await page.evaluate(()=>GeoLive.search('企业应该怎样选择数据分析工具？'));
  const realtime=await metrics();assert.deepEqual(realtime,teaching);assert.equal(await page.evaluate(()=>state.ds.byId.S2.display_site),'工具文档');assert.equal(await page.evaluate(()=>state.ds.byId.S2.ic),'工');
  assert.equal(await page.locator('#side .srcs > .src').count(),2);
  assert.equal(await page.locator('#side .src a.src-t').count(),2);
  assert((await page.locator('#r-banner').innerText()).includes('简体中文优先'));
  assert(!(await page.locator('#r-banner').innerText()).includes('含补充语言信源'));
  assert((await page.locator('#side .srcs .live-source-language').nth(0).innerText()).includes('简体中文'));
  assert((await page.locator('#side .srcs .live-source-language').nth(1).innerText()).includes('简体中文'));
  assert(!(await page.locator('#side .srcs .live-source-language').nth(1).innerText()).includes('补充信源'));
  const languageRanking=await page.evaluate(()=>{
    const rows=[{...state.ds.sources[0],id:'simple',language_priority:0,sig:[10,10,10,10,10,10]},
      {...state.ds.sources[1],id:'foreign',language_priority:2,language_allowed:false,sig:[100,100,100,100,100,100]},
      {...state.ds.sources[1],id:'traditional',language_priority:1,sig:[99,99,99,99,99,99]}];
    const unknown={...rows[0],id:'unknown',sig:[null,null,null,null,null,null]};return {order:rankBy({live:true,sources:rows},DEFAULT_W).map(x=>x.s.id),selectable:rows.map(sourceSelectable),unknownOrder:rankBy({live:true,sources:[unknown,rows[2]]},DEFAULT_W).map(x=>x.s.id)};
  });
  assert.deepEqual(languageRanking.order,['simple','traditional','foreign']);
  assert.deepEqual(languageRanking.selectable,[true,false,true]);assert.deepEqual(languageRanking.unknownOrder,['traditional','unknown']);
  assert.equal(await page.locator('#side .srcs [data-api-metric="authority"]').first().innerText(),'网页权威 3 / 4');
  assert(await page.locator('#side .srcs [data-api-metric="authority"]').first().isVisible());
  assert.equal(await page.locator('#side .srcs [data-api-metric="rerank"]').first().innerText(),'搜索排序 2.65 / 3');
  assert.equal(await page.locator('#pipe .pipe-mini').count(),1);
  await page.locator('#xswitch').click();assert.equal(await page.locator('#pipe .pstep').count(),6);
  await page.locator('#side .src').first().hover();
  assert(await page.locator('#answer').evaluate(el=>el.classList.contains('dim')));
  await page.locator('#answer .seg').first().click();await page.locator('#pop').waitFor({state:'visible'});
  assert.equal(await page.locator('#pop .live-evidence-foot a').count(),2);
  assert.equal(await page.locator('#pop [data-api-metric="authority"]').first().innerText(),'网页权威 3 / 4');
  assert.equal(await page.locator('#pop [data-api-metric="rerank"]').first().innerText(),'搜索排序 2.65 / 3');
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  const popup=await page.locator('#pop').boundingBox();assert(popup.height<=560 && popup.y>=76 && popup.y+popup.height<=900,'Long evidence popup outside viewport: '+JSON.stringify(popup));
  assert(await page.locator('#pop').evaluate(el=>el.scrollHeight>el.clientHeight));
  await page.evaluate(()=>closePop());
  assert.equal(await page.locator('#answer img,#side img').count(),0);
  assert.equal(await page.evaluate(()=>window.__geoXSS),undefined);
  const edgeMetrics=await page.evaluate(()=>[sourceMetrics({authority:-1,api_score:0}),sourceMetrics({authority:0,api_score:3}),sourceMetrics({authority:null,api_score:null})]);
  assert(edgeMetrics[0].includes('未知'));assert(edgeMetrics[0].includes('0.00 / 3'));
  assert(edgeMetrics[1].includes('0 / 4'));assert(edgeMetrics[1].includes('3.00 / 3'));
  assert(!edgeMetrics[2].includes('null'));assert(!edgeMetrics[2].includes('NaN'));
  await page.screenshot({path:path.join(artifacts,'results-desktop.png'),fullPage:true});
  await page.evaluate(()=>openProcess(2));assert.equal(await page.locator('.weights input[type=range]').count(),6);
  await page.locator('#rank-source').focus();await page.keyboard.press('ArrowRight');
  const selectStage=await page.evaluate(()=>state.stage);
  await page.evaluate(()=>openProcess(2));await page.locator('#rank-source').selectOption('S2');
  await resize(390);
  const responsive=await page.locator('#board .brow').evaluateAll(nodes=>{const rows=nodes.map(el=>el.getBoundingClientRect()).sort((a,b)=>a.top-b.top);return{gap:rows[1].top-rows[0].bottom,height:rows[0].height};});
  console.log(JSON.stringify({selectStage,responsive}));
  assert.equal(selectStage,2,'Arrow keys in source select must not navigate away');
  assert(responsive.gap>=-0.1,'Ranking rows overlap after resizing in place');assert.equal(await page.locator('#rank-source').inputValue(),'S2');
  await resize(1440);
  const beforePreview=requests.length, originalAnswer=await page.evaluate(()=>JSON.stringify(state.ds.answer));
  await page.getByRole('button',{name:'只看相关性',exact:true}).click();
  assert.equal(await page.locator('.brow[data-rank="1"]').getAttribute('data-id'),'S1');
  await page.getByRole('button',{name:'权威优先',exact:true}).click();
  assert.equal(await page.locator('.brow[data-rank="1"]').getAttribute('data-id'),'S2');
  assert.equal(requests.length,beforePreview);assert.equal(await page.evaluate(()=>JSON.stringify(state.ds.answer)),originalAnswer);
  assert.equal(await page.locator('#rank-breakdown>div').count(),6);
  await page.locator('#rank-apply').click();await page.waitForFunction(()=>!!state.ds&&!state.thinking);
  assert.equal(requests.length,beforePreview+1);assert.equal(requests.at(-1).weights.auth,40);
  await page.evaluate(()=>openProcess(2));assert(await page.locator('#rank-apply').isDisabled());
  await page.locator('#w-rel').focus();await page.keyboard.press('ArrowRight');assert.equal(await page.locator('#w-rel').inputValue(),'35');assert.equal(await page.evaluate(()=>state.stage),2);
  await page.evaluate(()=>{for(const g of SIG){const input=document.querySelector('#w-'+g.k);input.value=0;input.dispatchEvent(new Event('input',{bubbles:true}));}});
  assert(await page.locator('#rank-apply').isDisabled());assert((await page.locator('#rank-status').innerText()).includes('非零'));
  await page.getByRole('button',{name:'默认',exact:true}).click();
  await page.locator('#next').click();assert.equal(await page.evaluate(()=>state.stage),3);
  assert.equal(await page.locator('.chunk.pick').count(),2);assert.equal(await page.locator('.chunk.drop').count(),2);
  await page.locator('#prev').click();assert.equal(await page.evaluate(()=>state.stage),2);
  await page.locator('#panel h2').click();await page.keyboard.press('ArrowRight');assert.equal(await page.evaluate(()=>state.stage),3);
  await page.evaluate(()=>openProcess(5));assert.equal(await page.locator('.check input').count(),6);await page.locator('#ck-0').check();
  await page.evaluate(()=>goStage(4));await page.evaluate(()=>goStage(5));assert(await page.locator('#ck-0').isChecked());
  await page.evaluate(()=>backToResults());

  for(const width of [1440,1024,768,640,390,320]){
   await resize(width);
   await page.evaluate(()=>backToResults());
   assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Result overflow at '+width);
   for(let stage=0;stage<6;stage++){
    await page.evaluate(stage=>openProcess(stage),stage);
    assert((await page.locator('#panel').innerText()).length>20,'Empty stage '+stage);
    if(stage===2){const funnel=await page.locator('.funnel .fn>div').allTextContents();const counts=funnel.map(Number);assert(counts.every((n,i)=>i===0||n<=counts[i-1]),'Ranking funnel must not grow after quality filtering');}
    if(stage===5){assert.equal(await page.locator('.ccard [data-api-metric="authority"]').count(),2);assert.equal(await page.locator('.ccard [data-api-metric="rerank"]').count(),2);}
    if(width===1440)await page.screenshot({path:path.join(artifacts,'process-stage-'+(stage+1)+'.png'),fullPage:true});
    if(width===390&&stage===2)await page.screenshot({path:path.join(artifacts,'ranking-mobile.png'),fullPage:true});
    const bounds=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth}));
    assert(bounds.scroll<=bounds.width,'Stage '+stage+' overflow '+JSON.stringify(bounds));
    if(stage===4)assert(await page.locator('.mrow .tx').evaluateAll(nodes=>nodes.every(node=>node.getBoundingClientRect().width>120)));
   }
  }
  await page.screenshot({path:path.join(artifacts,'process-mobile.png'),fullPage:true});
  await page.evaluate(()=>backToResults());await page.locator('#answer .seg').first().click();
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  const sheet=await page.locator('#pop').boundingBox();assert(sheet.x>=-1 && sheet.x+sheet.width<=321 && sheet.y+sheet.height<=1001,'Mobile evidence sheet outside viewport: '+JSON.stringify(sheet));await page.evaluate(()=>closePop());
  await resize(1440);await page.evaluate(()=>GeoLive.search('语言补充测试'));
  assert((await page.locator('#r-banner').innerText()).includes('含补充语言信源'));
  assert((await page.locator('#side .srcs .live-source-language').nth(0).innerText()).includes('繁体中文'));
  assert((await page.locator('#side .srcs .live-source-language').nth(1).innerText()).includes('英文'));
  assert.equal(await page.locator('#side .srcs .live-source-language').filter({hasText:'补充信源'}).count(),2);
  await page.screenshot({path:path.join(artifacts,'language-fallback-desktop.png'),fullPage:true});
  for(const width of [390,320]){await resize(width);assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));}
  await page.screenshot({path:path.join(artifacts,'language-fallback-mobile.png'),fullPage:true});
  await resize(1440);await page.evaluate(()=>GeoLive.search('数学分析师推荐'));
  assert(await page.locator('.live-empty').isVisible());assert(await page.locator('#legend').isHidden());assert.equal(await page.locator('#answer .cite').count(),0);
  for(let stage=0;stage<6;stage++){await page.evaluate(stage=>openProcess(stage),stage);assert((await page.locator('#panel').innerText()).length>20);if(stage===2){const counts=(await page.locator('.funnel .fn>div').allTextContents()).map(Number);assert(counts.every((n,i)=>i===0||n<=counts[i-1]),'Empty-result funnel must not reintroduce rejected candidates');}}
  await page.evaluate(()=>backToResults());await page.screenshot({path:path.join(artifacts,'insufficient-desktop.png'),fullPage:true});
  for(const width of [390,320]){await resize(width);assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));}
  await page.screenshot({path:path.join(artifacts,'insufficient-mobile.png'),fullPage:true});
  await page.evaluate(()=>GeoLive.search('错误状态测试'));assert((await page.locator('#answer [role=alert]').innerText()).includes('离线限流测试'));
  await page.locator('#q-res').fill('等待检索测试');await page.locator('#f-res').getByRole('button',{name:'搜索',exact:true}).click();
  await page.locator('#live-cancel').waitFor({state:'visible'});assert.equal(await page.locator('.live-phase').count(),6);assert.equal(await page.locator('.live-phase.cur').count(),1);assert(await page.locator('#legend').isHidden());await page.screenshot({path:path.join(artifacts,'loading-mobile.png'),fullPage:true});
  await page.locator('#live-cancel').focus();
  waitingResponse.write('event: step\ndata: '+JSON.stringify({stage:1,message:'正在检索资料。'})+'\n\n');
  await page.waitForFunction(()=>document.querySelector('.live-phase.cur')?.textContent.includes('检索召回'));
  assert(await page.locator('#live-cancel').evaluate(el=>document.activeElement===el),'Progress updates must preserve the focused cancel action');
  await page.locator('#live-cancel').click();await page.waitForFunction(()=>!state.thinking);
  assert.equal(await page.locator('.live-spinner').count(),0);
  assert((await page.locator('#answer [role=alert]').innerText()).includes('已停止'));
  await resize(1440);
  await page.emulateMedia({colorScheme:'dark'});await page.evaluate(()=>GeoLive.search('企业应该怎样选择数据分析工具？'));
  assert(await page.locator('#side .src').count()===2);await page.screenshot({path:path.join(artifacts,'results-dark.png'),fullPage:true});await page.emulateMedia({colorScheme:'light'});
  await page.getByRole('button',{name:'教学演示',exact:true}).click();await page.getByRole('button',{name:'数据分析推荐',exact:true}).click();await page.evaluate(()=>finishThink(false));
  assert.deepEqual(await metrics(),teaching);await page.evaluate(()=>openProcess(4));assert.equal(await page.locator('.mrow').count(),14);
  assert.deepEqual(errors,[]);
  console.log(JSON.stringify({result:'PASS',teaching,realtime,widths:[1440,1024,768,640,390,320],views:10,artifacts}));
 }finally{await browser.close();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error.stack);process.exitCode=1;});
