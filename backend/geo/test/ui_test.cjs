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
const sources = [
  {id:'S1',site:'一个名称较长的数据分析研究中心资料库',title:'数据分析工具选型与团队协作指南',url:'https://example.org/analysis',api_score:2.65,authority:3,date:'2026-11-01'},
  {id:'S2',site:'工具文档',title:'产品说明 <img src=x onerror="window.__geoXSS=1">',url:'https://example.net/guide',api_score:2.13,authority:2,date:'2026-10-30'}
].map((s,i)=>({...s,snip:text,tc:'#2d5bff',ic:s.site[0],r0:i,v0:s.api_score,type:'网页正文',read:true,eligible:true,why:'本次回答引用了此来源的选段。'}));
const evidence = sources.map(s=>({id:s.id+'-P1',source_id:s.id,text:text.repeat(24),basis:'body',term_hits:2}));
const refs = evidence.map(e=>({id:e.source_id,q:e.text,evidence_id:e.id,basis:e.basis}));
const data = {live:true,query:'企业应该怎样选择数据分析工具？',intent:{type:'工具选型'},searches:[{query:'企业应该怎样选择数据分析工具？ lang:zh',count:2},{query:'数据分析工具 团队协作 lang:zh',count:2}],sources,evidence,answer:[{t:'p',segs:[{x:text.repeat(4),f:refs}]},{t:'p',segs:[{x:text,f:[refs[0]]}]}],cited:['S1','S2'],trace:Array.from({length:6},(_,stage)=>({stage,message:['保留原始问题，生成搜索词。','实际检索 2 组查询。','按 1.50 分选用线筛选来源。','已记录 2 段正文。','已整理 2 段回答。','引用 2 个来源。'][stage]})),total:4,dedup:2,cached:false,status:'complete',quality:{min_score:1.5,eligible_count:2,read_count:2,language:'zh'},warnings:[],created_at:'2026-11-01T19:00:00+08:00',elapsed_seconds:2.18,budget:{limit_cny:50,used_cny:0.12,remaining_cny:49.88}};
let loggedIn = false;
const files = {'/geo/':['geo/index.html','text/html'],'/geo/live.js':['geo/live.js','text/javascript'],'/geo/live.css':['geo/live.css','text/css'],'/geo/test-questions.json':['geo/test-questions.json','application/json']};
const json = (res, value, code=200) => {res.writeHead(code, {'Content-Type':'application/json'});res.end(JSON.stringify(value));};
const server = http.createServer(async(req,res)=>{
  const pathname = new URL(req.url,'http://localhost').pathname;
  if(pathname==='/geo/api/status') return json(res,{configured:true,authenticated:loggedIn,budget:data.budget});
  if(pathname==='/geo/api/session'){loggedIn=req.method==='POST';return json(res,{authenticated:loggedIn,budget:data.budget});}
  if(pathname==='/geo/api/search'){
    let body='';for await(const chunk of req) body+=chunk;
    const question=JSON.parse(body).question;
    if(question==='错误状态测试') return json(res,{error:{message:'离线限流测试，请稍后再试。'}},429);
    res.writeHead(200,{'Content-Type':'text/event-stream; charset=utf-8'});
    if(question==='等待检索测试'){res.write('event: step\ndata: {"stage":0,"message":"正在理解问题。"}\n\n');return;}
    const output=structuredClone(data);output.query=question;
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
  await page.evaluate(()=>openProcess(0));
  assert(await page.locator('#home').isVisible());
  await page.evaluate(()=>GeoLive.search('企业应该怎样选择数据分析工具？'));
  const realtime=await metrics();assert.deepEqual(realtime,teaching);
  assert.equal(await page.locator('#side .srcs > .src').count(),2);
  assert.equal(await page.locator('#side .src a.src-t').count(),2);
  assert.equal(await page.locator('#pipe .pipe-mini').count(),1);
  await page.locator('#xswitch').click();assert.equal(await page.locator('#pipe .pstep').count(),6);
  await page.locator('#side .src').first().hover();
  assert(await page.locator('#answer').evaluate(el=>el.classList.contains('dim')));
  await page.locator('#answer .seg').first().click();await page.locator('#pop').waitFor({state:'visible'});
  assert.equal(await page.locator('#pop .live-evidence-foot a').count(),2);
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  const popup=await page.locator('#pop').boundingBox();assert(popup.height<=560 && popup.y>=76 && popup.y+popup.height<=900,'Long evidence popup outside viewport: '+JSON.stringify(popup));
  assert(await page.locator('#pop').evaluate(el=>el.scrollHeight>el.clientHeight));
  await page.evaluate(()=>closePop());
  assert.equal(await page.locator('#answer img,#side img').count(),0);
  assert.equal(await page.evaluate(()=>window.__geoXSS),undefined);
  await page.screenshot({path:path.join(artifacts,'results-desktop.png'),fullPage:true});
  for(const width of [1440,1024,768,640,390,320]){
   await resize(width);
   await page.evaluate(()=>backToResults());
   assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Result overflow at '+width);
   for(let stage=0;stage<6;stage++){
    await page.evaluate(stage=>openProcess(stage),stage);
    assert((await page.locator('#panel').innerText()).length>20,'Empty stage '+stage);
    if(width===1440)await page.screenshot({path:path.join(artifacts,'process-stage-'+(stage+1)+'.png'),fullPage:true});
    const bounds=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth}));
    assert(bounds.scroll<=bounds.width,'Stage '+stage+' overflow '+JSON.stringify(bounds));
    if(stage===4)assert(await page.locator('.mrow .tx').evaluateAll(nodes=>nodes.every(node=>node.getBoundingClientRect().width>120)));
   }
  }
  await page.screenshot({path:path.join(artifacts,'process-mobile.png'),fullPage:true});
  await page.evaluate(()=>backToResults());await page.locator('#answer .seg').first().click();
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  const sheet=await page.locator('#pop').boundingBox();assert(sheet.x>=-1 && sheet.x+sheet.width<=321 && sheet.y+sheet.height<=1001,'Mobile evidence sheet outside viewport: '+JSON.stringify(sheet));await page.evaluate(()=>closePop());
  await resize(1440);await page.evaluate(()=>GeoLive.search('数学分析师推荐'));
  assert(await page.locator('.live-empty').isVisible());assert(await page.locator('#legend').isHidden());assert.equal(await page.locator('#answer .cite').count(),0);
  for(let stage=0;stage<6;stage++){await page.evaluate(stage=>openProcess(stage),stage);assert((await page.locator('#panel').innerText()).length>20);}
  await page.evaluate(()=>backToResults());await page.screenshot({path:path.join(artifacts,'insufficient-desktop.png'),fullPage:true});
  for(const width of [390,320]){await resize(width);assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));}
  await page.screenshot({path:path.join(artifacts,'insufficient-mobile.png'),fullPage:true});
  await page.evaluate(()=>GeoLive.search('错误状态测试'));assert((await page.locator('#answer [role=alert]').innerText()).includes('离线限流测试'));
  await page.locator('#q-res').fill('等待检索测试');await page.locator('#f-res').getByRole('button',{name:'搜索',exact:true}).click();
  await page.locator('#live-cancel').waitFor({state:'visible'});assert.equal(await page.locator('.think.running .tstep').count(),1);
  await page.locator('#live-cancel').click();await page.waitForFunction(()=>!state.thinking);
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
