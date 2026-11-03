/* GEO internal search: authenticated requests and recorded evidence. */
(() => {
  'use strict';
  const api = '/geo/api';
  const modeButton = document.getElementById('beta-mode');
  const meter = document.getElementById('live-status');
  const tests = document.getElementById('live-tests');
  const original = {search, renderSide, renderThink, renderPipe, renderAnswer, renderLegend};
  const originalStages = {...STAGE_R};
  const originalAfter = {...STAGE_AFTER};
  const live = window.GeoLive = {active: false, controller: null, generation: 0, events: [], budget: null, rankingView: "api", weights: {...DEFAULT_W}};
  const money = value => Number(value || 0).toFixed(3);
  const safeURL = sourceURL;
  const sourceLink = s => `<a href="${esc(safeURL(s.url))}" target="_blank" rel="noopener noreferrer">${esc(s.title || s.site)}</a>`;
  const statusLabel = () => {
    if (!live.budget) return '内部试用 · 本次预算上限 50 元';
    return `内测预算 ¥${money(live.budget.limit_cny)} · 保守计费 ¥${money(live.budget.used_cny)} · 可用 ¥${money(live.budget.remaining_cny)}`;
  };
  function updateBudget(budget) {
    if (budget) live.budget = budget;
    meter.textContent = statusLabel();
    if (live.active) {
      const logout = document.createElement('button');
      logout.type = 'button'; logout.className = 'live-logout'; logout.textContent = '退出内测';
      logout.onclick = async () => {try {await request('/session', {method: 'DELETE'}); showMode(false);} catch (error) {toast(error.message);}};
      meter.append(' · ', logout);
    }
  }
  async function request(path, options = {}) {
    const response = await fetch(api + path, {credentials: 'same-origin', cache: 'no-store', ...options});
    let data;
    try {data = await response.json();} catch (_) {throw new Error('内测服务暂未连接，请稍后再试。');}
    if (!response.ok) throw new Error(data.error?.message || '请求未完成，请稍后再试。');
    return data;
  }
  function showMode(on) {
    live.active = on;
    document.body.classList.toggle('live-mode', on);
    try {sessionStorage.setItem('geo-mode', on ? 'live' : 'demo');} catch (_) {}
    modeButton.setAttribute('aria-pressed', String(on));
    modeButton.dataset.short = on ? '教学' : '内测';
    modeButton.querySelector('span').textContent = on ? '教学演示' : '实时内测';
    document.querySelector('.brand small').textContent = on ? '内测版' : '教学版';
    meter.hidden = !on;
    tests.hidden = !on;
    document.getElementById('q-home').placeholder = on ? '输入真实问题，开始联网检索…' : '问任何问题…';
    document.querySelectorAll('textarea').forEach(el => el.maxLength = 500);
    if (live.controller) live.controller.abort();
    live.generation++;
    clearTimeout(state.thinkT);
    state.thinking = false;
    state.ds = null;
    setView('home');
    document.getElementById('f-res').classList.remove('busy');
    updateBudget();
    document.getElementById('q-home').focus();
  }

  const dialog = document.createElement('dialog');
  dialog.className = 'live-dialog';
  dialog.setAttribute('aria-labelledby', 'live-dialog-title');
  dialog.innerHTML = `<form id="live-login"><h2 id="live-dialog-title">进入实时内测</h2><p id="live-dialog-copy">输入团队内测口令。登录状态保留 12 小时。</p><div id="live-password-wrap"><label for="live-password">内测访问口令</label><input id="live-password" type="password" autocomplete="current-password" maxlength="256" required></div><div class="live-error" id="live-login-error" role="alert"></div><div class="live-actions"><button type="button" id="live-close">返回</button><button type="submit" id="live-login-submit">进入内测</button></div></form>`;
  document.body.append(dialog);
  document.getElementById('live-close').onclick = () => dialog.close();
  async function enterLive() {
    modeButton.disabled = true;
    try {
      const status = await request('/status');
      updateBudget(status.budget);
      if (status.authenticated) {showMode(true); return;}
      const configured = status.configured;
      document.getElementById('live-dialog-copy').textContent = configured
        ? '输入团队内测口令。登录状态保留 12 小时。'
        : '实时内测尚未启用，请联系老姚完成配置。';
      document.getElementById('live-password-wrap').hidden = !configured;
      document.getElementById('live-login-submit').hidden = !configured;
      document.getElementById('live-login-error').textContent = '';
      dialog.showModal();
      if (configured) document.getElementById('live-password').focus();
    } catch (error) {
      document.getElementById('live-dialog-copy').textContent = error.message;
      document.getElementById('live-password-wrap').hidden = true;
      document.getElementById('live-login-submit').hidden = true;
      document.getElementById('live-login-error').textContent = '';
      dialog.showModal();
    } finally {modeButton.disabled = false;}
  }
  modeButton.onclick = () => live.active ? showMode(false) : enterLive();
  document.getElementById('live-login').onsubmit = async event => {
    event.preventDefault();
    const button = document.getElementById('live-login-submit');
    const password = document.getElementById('live-password');
    button.disabled = true;
    try {
      const data = await request('/session', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({password: password.value})});
      password.value = '';
      updateBudget(data.budget);
      dialog.close();
      showMode(true);
    } catch (error) {document.getElementById('live-login-error').textContent = error.message;}
    finally {button.disabled = false;}
  };
  dialog.addEventListener('close', () => {document.getElementById('live-password').value = '';});

  fetch('/geo/test-questions.json').then(r => r.ok ? r.json() : []).then(questions => {
    const list = document.getElementById('live-test-list');
    questions.forEach(item => {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = `${item.category} · ${item.question}`;
      button.title = item.check;
      button.onclick = () => {
        const input = document.getElementById('q-home');
        input.value = item.question;
        input.dispatchEvent(new Event('input', {bubbles: true}));
        input.focus();
      };
      list.append(button);
    });
  }).catch(() => {});

  const arrow = '<svg class="car" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m6 9 6 6 6-6"/></svg>';
  const check = '<span class="ok"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12 5 5 9-10"/></svg></span>';
  const selectedCount = ds => ds.quality?.read_count ?? ds.sources.filter(s => s.read !== false).slice(0, 5).length;
  const languageLabel = ds => (ds.quality?.preferred_language||ds.quality?.language||'').split(',').map(code=>({'zh-Hans':'简体中文','zh-Hant':'繁体中文',zh:'中文',en:'英文'})[code]||code).join('、') || '不限';
  const sourceLanguageLabel = ds => [ds.quality?.strict_language?languageLabel(ds)+'限定':ds.quality?.excluded_languages?.length?null:'不限', ...(ds.quality?.excluded_languages || []).map(code=>'排除'+(({'zh-Hans':'简体中文','zh-Hant':'繁体中文',zh:'中文',en:'英文'})[code]||code))].filter(Boolean).join('，');
  const stageRows = events => STAGES.map((_, index) => events.filter(event => event.stage === index).slice(-1)[0]).filter(Boolean);
  function progress() {
    const current = live.events[live.events.length - 1] || {stage:0};
    const el = document.getElementById('think');
    el.className = 'think running live-progress';
    if (!el.querySelector('.live-progress-head')) {
      el.innerHTML = `<div class="live-progress-head"><div class="live-progress-title"><span class="live-spinner" aria-hidden="true"></span><b></b><span class="mono"></span></div><button class="live-cancel press" type="button" id="live-cancel">停止搜索</button></div><span class="live-progress-status" role="status" aria-live="polite" aria-atomic="true"></span><ol class="live-phase-list" aria-label="实时检索进度">${STAGES.map(stage=>`<li class="live-phase"><span class="live-phase-num"></span><span>${esc(stage.n)}</span></li>`).join('')}</ol>`;
      document.getElementById('live-cancel').onclick = () => live.controller?.abort();
    }
    const label = STAGES[current.stage].n;
    el.querySelector('.live-progress-title b').textContent = label;
    el.querySelector('.live-progress-title .mono').textContent = `0${current.stage + 1} / 06`;
    const status = el.querySelector('.live-progress-status');
    const announcement = `正在${label}，第 ${current.stage + 1} 步，共 6 步。`;
    if (status.textContent !== announcement) status.textContent = announcement;
    el.querySelectorAll('.live-phase').forEach((phase, index) => {
      phase.className = `live-phase ${index < current.stage ? 'done' : index === current.stage ? 'cur' : 'waiting'}`;
      if (index === current.stage) phase.setAttribute('aria-current', 'step');
      else phase.removeAttribute('aria-current');
      phase.querySelector('.live-phase-num').textContent = index < current.stage ? '✓' : index + 1;
    });
  }

  function renderRunMeta(data) {
    const meta = [data.ranking?.mode==='teaching'?'六维教学实验回答':'DeepSeek 综合分排序',...(data.quality?.strict_language||data.quality?.excluded_languages?.length?[sourceLanguageLabel(data)]:[]), data.cached ? '相同问题缓存' : '实时联网检索', `${data.cached ? '原检索' : '用时'} ${data.elapsed_seconds} 秒`, `累计 ¥${money(data.budget.used_cny)} / ¥${money(data.budget.limit_cny)}`];
    document.getElementById('r-banner').innerHTML = `<div class="live-run-meta">${meta.map(item => `<span>${esc(item)}</span>`).join('')}</div>${(data.warnings || []).map(text => `<div class="banner">${esc(text)}</div>`).join('')}`;
  }
  function prepare(data) {
    if (!data.live || !Array.isArray(data.sources) || !Array.isArray(data.answer) || !Array.isArray(data.cited)) throw new Error('内测返回的数据格式有误。');
    data.byId = Object.fromEntries(data.sources.map(source => [source.id, source]));
    if (data.cited.some(id => !data.byId[id])) throw new Error('来源对应关系不完整。');
    live.rankingView = data.ranking?.mode || "api";
    data.rank = rankBy(data, data.ranking?.weights || DEFAULT_W, live.rankingView);
    live.weights = {...(data.ranking?.weights || DEFAULT_W)};
    state.w = {...live.weights};
    data.color = {};
    data.sources.forEach((s, i) => {
      data.color[s.id] = (i % 5) + 1;
      s.tc = `var(--s${data.color[s.id]})`;
      let name = s.site;
      if (/^(?:[a-f\d]{2}){4,}$/i.test(name)) {
        try {
          const decoded = new TextDecoder('utf-8', {fatal:true}).decode(Uint8Array.from(name.match(/../g), pair=>parseInt(pair,16)));
          if (/^[\p{L}\p{N} .·_-]{2,}$/u.test(decoded)) name = decoded;
        } catch (_) { /* Keep names that do not form valid UTF-8. */ }
      }
      s.display_site = Array.from(name).length > 14 ? new URL(safeURL(s.url)).hostname.replace(/^www\./, '') : name;
      s.ic = Array.from(s.display_site)[0] || '·';
    });
    data.sents = [];
    data.answer.forEach(block => (block.segs || []).forEach(sg => {
      sg.evidence_refs = sg.evidence_refs || sg.f || [];
      const grouped = new Map();
      sg.evidence_refs.forEach(ref => {
        if (!data.byId[ref.id]) throw new Error('引用来源对应关系不完整。');
        if (!grouped.has(ref.id)) grouped.set(ref.id, {...ref, passages: []});
        grouped.get(ref.id).passages.push(ref);
      });
      sg.f = [...grouped.values()].map(ref => ({...ref, q: ref.passages.map(p => p.q).join('\n\n')}));
      sg.i = data.sents.length; data.sents.push(sg);
    }));
    data.subs = data.searches.map(s => [s.query, s.count, 0]);
    data.chunks = data.evidence.map(e => [e.text, 1, '']);
    data.picked = data.evidence.length;
    return data;
  }
  live.search = async (question, options = {}) => {
    question = String(question).trim();
    if (!question || question.length > 500) {toast('请输入 1～500 个字符的问题'); return;}
    const rankingMode = options.ranking_mode || "api";
    const weights = {...(rankingMode === "teaching" ? options.weights || live.weights : DEFAULT_W)};
    if (!SIG.some(g=>weights[g.k]>0)) {toast('至少保留一个非零权重'); return;}
    if (live.controller) live.controller.abort();
    const controller = new AbortController();
    live.controller = controller;
    const generation = ++live.generation;
    clearTimeout(state.thinkT);
    state.ds = null; state.q = question; state.pin = null; state.stage = 0; state.fallback = false; state.thinking = true;
    setView('results');
    document.getElementById('r-q').textContent = question;
    for (const id of ['answer', 'pipe', 'r-banner']) document.getElementById(id).innerHTML = '';
    document.getElementById('side').innerHTML = '<div class="sec-h"><b>来源</b><span>检索完成后展示</span></div><div class="live-source-placeholder" aria-hidden="true"><i></i><i></i><i></i></div>';
    document.getElementById('legend').innerHTML = '';
    document.getElementById('legend').hidden = true;
    document.getElementById('f-res').classList.add('busy');
    live.events = [{stage: 0, message: '连接内测服务。'}];
    progress();
    let completed = false;
    try {
      const response = await fetch(api + '/search', {method: 'POST', credentials: 'same-origin', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({question, weights, ranking_mode: rankingMode}), signal: controller.signal});
      if (!response.ok) {
        const data = await response.json().catch(() => ({}));
        throw new Error(data.error?.message || '内测服务暂未完成请求。');
      }
      if (!response.body || !response.headers.get('content-type')?.includes('text/event-stream')) throw new Error('服务器未返回可用的搜索进度。');
      const reader = response.body.getReader(), decoder = new TextDecoder();
      let pending = '';
      const receive = block => {
        const event = block.split('\n').find(line => line.startsWith('event:'))?.slice(6).trim();
        const raw = block.split('\n').filter(line => line.startsWith('data:')).map(line => line.slice(5).trimStart()).join('\n');
        if (!raw || generation !== live.generation) return;
        const data = JSON.parse(raw);
        if (event === 'step') {live.events.push(data); progress();}
        if (event === 'error') {updateBudget(data.budget);const error=new Error(data.message || '搜索未完成。');error.runId=data.run_id;throw error;}
        if (event === 'result') {
          state.ds = prepare(data); state.thinking = false;
          completed = true;
          updateBudget(data.budget);
          setView('results');
          renderLegend(); renderAnswer(false); renderThink(state.xray); renderSide(); renderPipe();
          renderRunMeta(data);
          document.getElementById('f-res').classList.remove('busy');
        }
      };
      while (true) {
        const {value, done} = await reader.read();
        pending += decoder.decode(value, {stream: !done}).replace(/\r\n/g, '\n');
        let end;
        while ((end = pending.indexOf('\n\n')) >= 0) {receive(pending.slice(0, end)); pending = pending.slice(end + 2);}
        if (done) {if (pending.trim()) receive(pending); break;}
      }
      if (!completed && generation === live.generation) throw new Error('连接已结束，尚未收到完整回答，请稍后再试。');
    } catch (error) {
      if (generation !== live.generation) return;
      const message = error.name === 'AbortError' ? '已停止本次搜索。已发出的请求可能计费，用量会保守记录。' : error.message;
      document.getElementById('think').innerHTML = '';
      document.getElementById('answer').innerHTML = `<p class="live-answer-error" role="alert">${esc(message)}</p>${/^[a-f0-9]{32}$/.test(error.runId||'')?`<a class="linkbtn" href="/geo/api/runs/${error.runId}" download>下载本次诊断记录</a>`:''}`;
      document.getElementById('side').innerHTML = '';
    } finally {
      if (generation === live.generation) {state.thinking = false; live.controller = null; document.getElementById('f-res').classList.remove('busy');}
    }
  };
  search = function(question, id) {return live.active ? live.search(question) : original.search(question, id);};
  renderLegend = function() {
    document.getElementById('legend').hidden = state.ds?.status === 'insufficient';
    if (!state.ds?.live) return original.renderLegend();
    if (state.ds.status === 'insufficient') {document.getElementById('legend').innerHTML = ''; return;}
    original.renderLegend();
    document.getElementById('legend').querySelectorAll('.lg').forEach(el => {if (el.textContent === '模型组织') el.remove();});
  };
  function formattedAnswer(ds, anim) {
    let html='',section='',sectionCount=0,inSection=false,inList=false;
    const closeList=()=>{if(inList){html+='</ul>';inList=false;}};
    const closeSection=()=>{closeList();if(inSection){html+='</section>';inSection=false;}};
    ds.answer.forEach((block,index)=>{
      const content=(block.segs||[]).map(segment=>segHTML(segment,ds,anim)).join('');
      const heading=typeof block.heading==='string'?block.heading.trim():'';
      if(index===0){html+=`<p class="live-answer-summary">${content}</p>`;return;}
      if(heading&&heading!==section){
        closeSection();section=heading;sectionCount++;inSection=true;
        html+=`<section class="live-answer-section"><h3><span class="live-section-number" aria-hidden="true">${sectionCount}.</span><span>${esc(heading)}</span></h3>`;
      }
      if(block.kind==='bullet'){
        if(!inList){html+='<ul class="live-answer-points">';inList=true;}
        html+=`<li>${content}</li>`;
      }else{closeList();html+=`<p>${content}</p>`;}
    });
    closeSection();return html;
  }
  function insufficiencyDetails(ds) {
    const reasons=ds.quality?.insufficiency_reasons || [];
    return reasons.length ? `<ul class="live-empty-reasons">${reasons.map(r=>`<li data-insufficiency="${esc(r.code)}"><p>${esc(r.message)}</p><small>${esc(r.action)}</small></li>`).join('')}</ul>` : `<p>${esc(ds.diagnostic || '本次未取得可用证据。')}</p>`;
  }
  renderAnswer = function(anim) {
    const ds = state.ds;
    if (ds?.live && ds.status === 'insufficient') {
      const suggestion = ds.query.includes('推荐') ? '“推荐”可以指工具、专家或岗位。把推荐对象和使用场景写清楚，有助于找到更相关的资料。' : '补充主题或产品的完整名称、时间和适用地区，有助于找到更相关的资料。';
      document.getElementById('answer').innerHTML = `<div class="surface live-empty"><span class="live-empty-label">资料不足</span><h2>补充一点条件，再继续搜索</h2>${insufficiencyDetails(ds)}<p class="live-note">${esc(suggestion)}</p></div>`;
      return;
    }
    if(ds?.live){revealN=0;document.getElementById('answer').innerHTML=formattedAnswer(ds,anim);}
    else original.renderAnswer(anim);
    if (ds?.live) document.querySelectorAll('#answer .ktag').forEach((tag, i) => tag.textContent = ds.sents[i].f.length > 1 ? '多源引用' : '单源引用');
  };
  live.decoratePop = function(pop, sentence) {
    pop.scrollTop = 0;
    pop.querySelector('.desc').textContent = '这段回答关联的原始选段如下，可打开网页核对上下文。';
    pop.querySelector('.kbadge').textContent = sentence.f.length > 1 ? '多源引用' : '单源引用';
    pop.querySelectorAll('.tsrc').forEach((el, i) => {
      const ref = sentence.f[i], source = state.ds.byId[ref.id];
      el.querySelector('.tsrc-h').innerHTML = `${ico(source)}<span class="live-source-name">${esc(short(source))}</span>`;
      el.querySelector('.tsrc-h').insertAdjacentHTML('afterend',sourceMetrics(source));
      el.querySelector('blockquote').outerHTML = `<div class="live-evidence-passages">${ref.passages.map(p => `<div><small class="mono">${esc(p.evidence_id)} · ${p.basis === 'body' ? '网页正文' : '搜索摘要'}</small><blockquote>${esc(p.q)}</blockquote></div>`).join('')}</div>`;
      el.insertAdjacentHTML('beforeend', `<div class="live-evidence-foot"><span>${esc(ref.passages.map(p=>p.evidence_id).join(' · '))} · ${ref.passages.length} 段关联证据</span><a href="${esc(safeURL(source.url))}" target="_blank" rel="noopener noreferrer">打开原文 ${ARROW}</a></div>`);
    });
  };
  renderSide = function(loading) {
    if (!state.ds?.live) return original.renderSide(loading);
    const ds = state.ds, misses = ds.sources.filter(s => !ds.cited.includes(s.id));
    document.getElementById('side').innerHTML = `<div class="sec-h"><b>来源</b><span>${ds.cited.length} 个引用</span></div><p class="live-score-note">DeepSeek 返回值 · 权威 0～4 · 排序 0～3</p><div class="srcs">${ds.cited.map((id, i) => srcCard(ds.byId[id], ds, i)).join('')}</div>${misses.length ? `<div class="xcard"><div class="sec-h"><b>未采用的候选</b><span>${misses.length} 个</span></div><p class="sub">1.50 分优先，1.00 分兜底；补充资料须通过完整内容与查询主题词检查。</p>${misses.slice(0, 3).map(s => `<div class="miss"><div class="miss-h"><b title="${esc(s.site)}">${esc(short(s))}</b><span class="gap">${apiScoreText(s.api_score)} / 3</span></div><p>${esc(s.why)}</p></div>`).join('')}<button class="linkbtn press" id="live-candidates">查看全部候选 ${ARROW}</button></div>` : ''}`;
    document.getElementById('live-candidates')?.addEventListener('click', () => openProcess(2));
    bindSourceCards();
  };
  renderThink = function(open) {
    if (!state.ds?.live) return original.renderThink(open);
    const ds = state.ds, rows = stageRows(ds.trace), el = document.getElementById('think');
    el.className = 'think' + (open ? ' open' : '');
    el.innerHTML = `<button class="think-h" id="think-t" aria-expanded="${!!open}">${check}<span>已检索 ${ds.searches.length} 组 · 精读 ${selectedCount(ds)} 页</span>${arrow}</button><div class="think-body"><div><div class="tlist">${rows.map(row => `<div class="tstep show done">${esc(row.message)}<button class="more" data-live-stage="${row.stage}">查看过程 →</button>${row.stage === 1 ? `<div class="sq">${ds.searches.map(s => `<span>${esc(s.query)}</span>`).join('')}</div>` : ''}</div>`).join('')}</div></div></div>`;
    document.getElementById('think-t').onclick = () => {const on = !el.classList.contains('open'); el.classList.toggle('open', on); document.getElementById('think-t').setAttribute('aria-expanded', String(on));};
    el.querySelectorAll('[data-live-stage]').forEach(button => button.onclick = () => openProcess(Number(button.dataset.liveStage)));
  };
  renderPipe = function() {
    if (!state.ds?.live) return original.renderPipe();
    const ds = state.ds, counts = [ds.searches.length, ds.dedup, selectedCount(ds), ds.evidence.length, ds.sents.length, ds.cited.length];
    const contents = state.xray
      ? `<div class="pipe-h"><b>这次检索经历了 6 个步骤</b><button class="linkbtn press" id="live-pipe-go">逐步查看 ${ARROW}</button></div><div class="pipe-steps">${STAGES.map((stage, i) => `<button class="pstep press" data-live-stage="${i}" type="button"><small>0${i + 1} ${stage.n}</small><strong>${counts[i]}</strong><span>${['个搜索词', '个候选网页', '个精读来源', '段输入证据', '段回答', '个引用来源'][i]}</span></button>`).join('')}</div>`
      : `<span>打开 GEO 透视，查看本次检索、选段和引用过程。</span><button class="linkbtn press" id="live-pipe-go">查看检索过程 ${ARROW}</button>`;
    document.getElementById('pipe').innerHTML = `<div class="pipe${state.xray ? '' : ' pipe-mini'}">${contents}</div>`;
    document.getElementById('live-pipe-go').onclick = () => openProcess(0);
    document.querySelectorAll('#pipe [data-live-stage]').forEach(button => button.onclick = () => openProcess(Number(button.dataset.liveStage)));
  };

  live.dimensionName = index => ['API 综合分映射','API 权威等级','日期新近度','内容结构估计','词项独特度','跨站词项重合度'][index];
  live.rankingTabs = () => `<div class="live-ranking-tabs" role="group" aria-label="排序查看方式"><button type="button" data-ranking-view="api" aria-pressed="${live.rankingView==='api'}">DeepSeek 排序</button><button type="button" data-ranking-view="teaching" aria-pressed="${live.rankingView==='teaching'}">六维教学实验</button></div>`;
  live.bindRankingTabs = ds => {
    document.querySelectorAll('[data-ranking-view]').forEach(button => button.onclick = () => {live.rankingView=button.dataset.rankingView;renderProcess();});
    document.getElementById('live-apply-api')?.addEventListener('click',()=>live.search(ds.query,{ranking_mode:'api'}));
  };
  live.apiRanking = ds => {
    const rows=rankBy(ds,DEFAULT_W,'api');
    return `${live.rankingTabs()}<h2>按 DeepSeek 综合分排序</h2>${lead('各语言信源按 DeepSeek 综合分排序，1.50 分优先，1.00 分及以上、1.50 分以下的候选在精读名额不足时补充。补充选段检查完整语句与查询主题词，遵守用户明确指定的语言条件。')}<p class="live-rank-state">${ds.ranking?.mode==='teaching'?'当前预览 API 顺序，已有回答采用六维教学实验。':'本次回答采用 DeepSeek 综合分排序。'}${ds.ranking?.mode==='teaching'?'<button type="button" class="linkbtn press" id="live-apply-api">按 DeepSeek 排序重新生成</button>':''}</p><div class="live-native-ranks">${rows.map(({s},i)=>`<article class="live-native-row" data-native-id="${esc(s.id)}"><div class="live-native-heading"><span class="mono">${String(i+1).padStart(2,'0')}</span><div><b>${sourceLink(s)}</b><span class="live-native-site">${esc(short(s))} · ${esc(s.language_label || '语言待确认')}${s.language_assessment?.uncertain?' · 规则判断待核对':''}</span></div><strong class="mono">${apiScoreText(s.api_score)}<small> / 3</small></strong></div><div class="live-native-bar"><i style="width:${s.api_score/3*100}%"></i></div><p>${esc(s.why)}</p>${sourceMetrics(s)}<details class="live-occurrences"><summary>原始查询位次与处理依据</summary><p class="small">合并池 API 分数序 #${s.api_rank || i+1}；原始响应位次按每个查询分别记录</p>${(s.occurrences || []).map(o=>`<div><span class="mono">Q${o.query_index} · #${o.raw_rank}</span><span>API ${apiScoreText(o.api_score)} / 3</span><span>${o.truncated_fields?.length?'截断字段：'+esc(o.truncated_fields.join('、')):'字段均在保留长度内'}</span></div>`).join('') || '<p>此结果未记录逐查询位次</p>'}<p>${esc(s.language_basis || '')}；${esc(s.date)}</p></details></article>`).join('')}</div>`;
  };
  function diagnosticPanel(ds) {
    const valid=/^[a-f0-9]{32}$/.test(ds.run_id || '');
    const audit=ds.diagnostics;
    const costOrigin=ds.cached?'original':'current';
    const recordState=audit?.available?(audit.complete?'complete':'partial'):'unavailable';
    const recordLabel=recordState==='complete'?'处理留档完整':recordState==='partial'?'处理留档不完整，无法追溯的项目保持未知':'处理留档已清理或暂不可用';
    return `<details class="live-run-record"><summary>本次处理记录与引用核对范围</summary><p>引用编号与来源对应已检查，结论的证据支持程度可继续核对原文。</p><p>本次保留 ${(ds.evidence || []).length} 段输入证据，${ds.sents.reduce((n,s)=>n+s.evidence_refs.length,0)} 条证据引用关联。来源按钮按网页合并，弹层保留全部选段。</p>${audit?`<p data-run-cost-origin="${costOrigin}">${ds.cached?'原检索':'本次'}调用已结算 ¥${Number(audit.settled_cny).toFixed(4)}${audit.pending_cny?`，另有待确认预留 ¥${Number(audit.pending_cny).toFixed(4)}`:''}${ds.cached?'；本次缓存读取无新增调用':''}；全站累计单独显示</p><p data-run-record-state="${recordState}">${recordLabel}，记录最长保留 7 天，容量达到上限时优先清理旧记录。</p>`:''}${valid&&audit?.available?`<a class="linkbtn" href="/geo/api/runs/${ds.run_id}" download="geo-run-${ds.run_id}.json">下载本次诊断记录</a>`:'<p>本次诊断记录暂不可下载</p>'}</details>`;
  }

  const descriptions = [
    '保留原问题并生成少量等义查询，默认不限制信源语言；用户明确指定的语种与排除条件持续生效，实际搜索词保留记录。',
    '每组查询调用一次 DeepSeek Search，按实际返回数量汇总并校验链接并合并重复网址，保留跳过理由。',
    '优先检查 API 1.50 分及以上来源，精读不足五页时检查 1.00 分及以上、1.50 分以下的补充资料，各档默认按 API 综合分降序。补充资料须含完整语句并命中查询主题词，用户明确指定的语言条件持续生效。',
    '过滤标题、导航与无效短标签，保留正文选段；使用摘要时单独标明依据类型。',
    '资料充足时生成回答并核对引用编号。资料不足时保留检索记录，请用户补充条件。',
    '引用与候选分别记录，每条引用都能追溯到已保存的选段和原始网页。'
  ];
  const guidance = [
    ['把推荐对象、场景和地区写清楚。', '保留原词，避免把工具、岗位和专家混为同一个需求。', '需要外语原文时，可以在问题里明确说明。'],
    ['让网页标题和正文围绕同一个具体问题。', '本次只展示 Search 的实际返回数量。', '搜索语言会影响可召回的资料范围。'],
    ['默认使用 DeepSeek 综合分，资料语言保留供核对。', '权威等级、日期与结构信息用于核对，六维加权仅在教学实验中生效。', '公开原始查询位次和每一步排除理由，便于核对排序变化。'],
    ['正文提供完整事实和上下文，减少纯导航内容。', '引用正文与引用搜索摘要分别标记。', '可用段落不足时，补充更具体的查询条件。'],
    ['每段回答关联已存在的证据编号。', '多源引用表示关联多个来源，具体结论可继续核对原文。', '检索证据不足时，先澄清需求。'],
    ['打开引用链接核对上下文。', '未被这次回答引用的来源仍可在候选记录中查看。', '一次查询的引用情况只代表这次运行。']
  ];
  live.stageMeta = index => ({p: descriptions[index], g: guidance[index], t: STAGES[index].t});
  const lead = text => `<p class="lead">${esc(text)}</p>`;
  const emptyStage = text => `<div class="surface live-stage-empty">${esc(text)}</div>`;
  const liveStages = {
    understand: ds => `<h2>先读懂问题，再拆成子问题</h2>${lead('核对识别出的意图、实体与条件，再查看本次实际发出的搜索词。未说明的条件保留待确认。')}<div class="u-grid"><div class="u-card"><small>意图类型</small><div class="big">${esc(ds.intent.type || '综合问题')}</div></div><div class="u-card"><small>识别出的实体</small><div class="chips">${ds.intent.ents?.length?ds.intent.ents.map(e=>`<span>${esc(e)}</span>`).join(''):'<span>本次未单独识别</span>'}</div></div><div class="u-card"><small>问题条件</small><dl><dt>信源语言</dt><dd>${esc(sourceLanguageLabel(ds))}</dd>${(ds.intent.cons||[]).map(c=>`<dt>${esc(c[0])}</dt><dd>${esc(c[1])}</dd>`).join('')}</dl></div><div class="u-card"><small>回答规划</small><div class="live-plan">${esc(ds.intent.plan || '先检索原始问题，精读达标来源，再依据选段回答。')}</div></div></div><p class="subh">查询扇出 · 1 个问题 → ${ds.searches.length} 组查询</p><div class="fan" id="fan"><svg class="wires" id="wires"></svg><div class="fan-q" id="fanq">${esc(ds.query)}</div><ul class="fan-list">${ds.searches.map((s, i) => `<li><span>Q${i + 1}</span>${esc(s.query)}</li>`).join('')}</ul></div>`,
    retrieve: ds => {
      const max = Math.max(1, ...ds.searches.map(s => s.count));
      return `<h2>实际搜索结果汇入候选池</h2>${lead('每条横线表示查询实际返回数量。链接入口检查与重复合并分开计数，原始位次和截断信息随候选保留。')}<div class="r-legend"><span class="lg"><i style="background:var(--g1)"></i>Search 返回结果</span></div>${ds.searches.map((s, i) => `<div class="r-row"><span class="q" title="${esc(s.query)}"><span>Q${i + 1}</span>${esc(s.query)}</span><div class="bar"><i data-w="${s.count / max * 100}" style="background:var(--g1)"></i></div><span class="n mono">${s.count}</span></div>`).join('')}<div class="sum"><span>原始结果</span><b>${ds.total}</b><i>→</i><span>入口跳过</span><b>${ds.processing?.skipped_occurrences || 0}</b><i>→</i><span>重复出现</span><b>${ds.processing?.duplicate_occurrences || 0}</b><i>→</i><span>唯一网页</span><b>${ds.dedup}</b><em>过程页保留全部 ${ds.sources.length} 个可用候选，实际精读 ${selectedCount(ds)} 个来源。</em></div>`;
    },
    rank: ds => rankingLab(ds),
    chunk: ds => {
      const read = ds.sources.filter(s=>s.read);
      return `<h2>AI 读的是段落</h2>${lead('先过滤标题与导航，再按问题词命中数选择每页最多三段完整内容。蓝色为实际输入证据，灰色展示未采用的段落和原因。')}<div class="cmeta"><span>实际精读 <b>${selectedCount(ds)}</b> 页</span><span>进入上下文 <b>${ds.evidence.length}</b> 段</span></div>${read.length ? read.map((source, i) => {const segments=source.segments||ds.evidence.filter(e=>e.source_id===source.id).map((e,j)=>({...e,picked:true,index:j})); return `<details class="doc live-doc" ${i === 0 ? 'open' : ''}><summary class="doc-bar"><span class="live-doc-name">${esc(short(source))}</span><span class="u">${esc(safeURL(source.url))}</span><span>${segments.filter(e=>e.picked).length}/${segments.length} 段</span></summary><div class="doc-body"><p class="doc-title">${sourceLink(source)}</p>${segments.map(e=>`<div class="chunk ${e.picked?'pick':'drop'}"><p><span class="mono live-evidence-id">§${e.index+1}</span>${esc(e.text)}</p><div class="cs"><span>${e.basis==='body'?'网页正文':'搜索摘要'}</span><span>问题词命中 <b>${e.term_hits}</b></span><span class="ctag">${e.picked?'→ 进入上下文':'未采用'}</span></div>${e.reason?`<p class="live-chunk-reason">${esc(e.reason)}</p>`:''}</div>`).join('')}</div></details>`;}).join('') : emptyStage(ds.diagnostic || '本次没有精读来源，可补充检索条件。')}`;
    },
    generate: ds => {
      const single = ds.sents.filter(s => s.f.length === 1).length, multiple = ds.sents.length - single;
      return `<h2>把选段整理成有依据的回答</h2>${lead(ds.sents.length ? `本次生成 ${ds.sents.length} 段回答，下面展示每段与来源的对应关系。` : '本次资料不足，没有调用回答模型。检索记录完整保留，可以补充条件后继续。')}${ds.sents.length ? `<div class="comp"><i style="width:${single / ds.sents.length * 100}%;background:var(--accent)"></i><i style="width:${multiple / ds.sents.length * 100}%;background:var(--g4)"></i></div><div class="comp-l"><span class="lg"><i style="background:var(--accent)"></i>单源引用 <b>${single}</b></span><span class="lg"><i style="background:var(--g4)"></i>多源引用 <b>${multiple}</b></span></div><div class="map">${ds.sents.map((s, i) => `<div class="mrow"><span class="ix">${String(i + 1).padStart(2, '0')}</span><span class="tx">${esc(s.x)}</span><span class="fr"><span class="tagk ${s.f.length > 1 ? 'merge' : 'extract'}">${s.f.length > 1 ? '多源引用' : '单源引用'}</span>${s.f.map(f => `<span class="chip-s" style="--sc:var(--s${ds.color[f.id]})">${ico(ds.byId[f.id])}${esc(short(ds.byId[f.id]))}</span>`).join('')}</span></div>`).join('')}</div>` : emptyStage(ds.diagnostic || '请补充推荐对象、使用场景或地区。')}`;
    },
    cite: ds => {
      const misses = ds.sources.filter(s => !ds.cited.includes(s.id));
      return `<h2>${ds.cited.length} 个来源获得引用</h2>${lead('最多精读五个来源，最终引用由实际回答采用的证据决定。这里保留入选、落选与可执行的内容检查项。')}${ds.cited.length ? `<div class="cgrid">${ds.cited.map(id => {const s = ds.byId[id]; return `<div class="ccard" style="--sc:var(--s${ds.color[id]})"><div class="h">${ico(s)}<span>${esc(short(s))}</span><span class="scorev">${ds.ranking?.mode==='teaching'?(s.weighted_score==null?'未知':f1(s.weighted_score)):apiScoreText(s.api_score)}</span></div>${sourceMetrics(s)}<p>关联 <b>${ds.sents.filter(sg => sg.f.some(f => f.id === id)).length}</b> 段回答 · ${esc(s.type)}</p>${sourceLink(s)}</div>`;}).join('')}</div>` : emptyStage(ds.diagnostic || '本次没有形成引用。')}${misses.length ? `<p class="subh live-section-gap">落选来源 · 原因与优化方向</p>${misses.map(s => {const dims=(s.sig||[]).map((v,i)=>({v,i})).filter(x=>Number.isFinite(x.v)).sort((a,b)=>a.v-b.v);const weakest=ds.ranking?.mode==='teaching'?dims[0]:null;return `<div class="mcard live-miss-card"><div class="h">${ico(s)}<b>${esc(short(s))}</b><span class="meta">${esc(s.type)} · API ${apiScoreText(s.api_score)} / 3</span><span class="gap">${ds.ranking?.mode==='teaching'?(s.weighted_score==null?'未知':f1(s.weighted_score)):apiScoreText(s.api_score)}</span></div><div><small>本次未引用原因</small><p>${esc(s.why)}</p>${sourceLink(s)}</div><div class="fix"><small>可优先检查${weakest?' · '+SIG[weakest.i].n:''}</small><p>${esc(weakest?['让标题和正文围绕用户的具体问题展开。','补充可核实的机构、作者和原始出处。','核对日期并持续更新已变化的信息。','增加清晰标题、定义、列表与完整语句。','补充可核对的一手数据、案例或具体事实。','核对与其他独立来源的事实和适用范围。'][weakest.i]:'核对问题对象、资料语言、API 分数和正文是否提供有效证据。')}</p></div></div>`;}).join('')}` : ''}${diagnosticPanel(ds)}${contentChecklist(ds)}`;
    }
  };
  Object.keys(originalStages).forEach(key => STAGE_R[key] = ds => ds.live ? liveStages[key](ds) : originalStages[key](ds));
  Object.keys(originalAfter).forEach(key => STAGE_AFTER[key] = ds => {
    if (!ds.live || ['understand', 'retrieve', 'rank', 'cite'].includes(key)) return originalAfter[key](ds);
  });
  try {if (sessionStorage.getItem('geo-mode') === 'live') enterLive();} catch (_) {}
})();
