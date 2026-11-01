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
  const live = window.GeoLive = {active: false, controller: null, generation: 0, events: [], budget: null};
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
  const languageLabel = ds => ({zh: '中文', en: '英文', 'zh,en': '中英文'})[ds.quality?.language] || '按问题语言';
  const stageRows = events => STAGES.map((_, index) => events.filter(event => event.stage === index).slice(-1)[0]).filter(Boolean);
  function progress() {
    const rows = stageRows(live.events);
    const el = document.getElementById('think');
    el.className = 'think running';
    el.innerHTML = `<div class="think-h"><span class="shimmer">${esc(rows[rows.length - 1]?.message || '正在联网检索…')}</span></div><div class="think-body"><div><div class="tlist">${rows.map((row, i) => `<div class="tstep show ${i === rows.length - 1 ? 'cur' : 'done'}">${esc(row.message)}</div>`).join('')}</div></div></div><button class="linkbtn press live-cancel" type="button" id="live-cancel">停止本次搜索</button>`;
    document.getElementById('live-cancel').onclick = () => live.controller?.abort();
  }
  function renderRunMeta(data) {
    const meta = [data.cached ? '相同问题缓存' : '实时联网检索', `${data.cached ? '原检索' : '用时'} ${data.elapsed_seconds} 秒`, `累计 ¥${money(data.budget.used_cny)} / ¥${money(data.budget.limit_cny)}`];
    document.getElementById('r-banner').innerHTML = `<div class="live-run-meta">${meta.map(item => `<span>${esc(item)}</span>`).join('')}</div>${(data.warnings || []).map(text => `<div class="banner">${esc(text)}</div>`).join('')}`;
  }
  function prepare(data) {
    if (!data.live || !Array.isArray(data.sources) || !Array.isArray(data.answer) || !Array.isArray(data.cited)) throw new Error('内测返回的数据格式有误。');
    data.byId = Object.fromEntries(data.sources.map(source => [source.id, source]));
    if (data.cited.some(id => !data.byId[id])) throw new Error('来源对应关系不完整。');
    data.rank = data.sources.map(s => ({s, v: s.api_score}));
    data.color = {};
    data.sources.forEach((s, i) => {
      data.color[s.id] = (i % 5) + 1;
      s.tc = `var(--s${data.color[s.id]})`;
      s.display_site = Array.from(s.site).length > 14 ? new URL(safeURL(s.url)).hostname.replace(/^www\./, '') : s.site;
    });
    data.sents = [];
    data.answer.forEach(block => (block.segs || []).forEach(sg => {sg.i = data.sents.length; data.sents.push(sg);}));
    data.subs = data.searches.map(s => [s.query, s.count, 0]);
    data.chunks = data.evidence.map(e => [e.text, 1, '']);
    data.picked = data.evidence.length;
    return data;
  }
  live.search = async question => {
    question = String(question).trim();
    if (!question || question.length > 500) {toast('请输入 1～500 个字符的问题'); return;}
    if (live.controller) live.controller.abort();
    const controller = new AbortController();
    live.controller = controller;
    const generation = ++live.generation;
    clearTimeout(state.thinkT);
    state.ds = null; state.q = question; state.pin = null; state.stage = 0; state.fallback = false; state.thinking = true;
    setView('results');
    document.getElementById('r-q').textContent = question;
    for (const id of ['answer', 'pipe', 'r-banner']) document.getElementById(id).innerHTML = '';
    document.getElementById('side').innerHTML = '<div class="sec-h">本次来源将在检索完成后展示</div>';
    document.getElementById('legend').innerHTML = '';
    document.getElementById('f-res').classList.add('busy');
    live.events = [{stage: 0, message: '连接内测服务。'}];
    progress();
    let completed = false;
    try {
      const response = await fetch(api + '/search', {method: 'POST', credentials: 'same-origin', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({question}), signal: controller.signal});
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
        if (event === 'error') {updateBudget(data.budget); throw new Error(data.message || '搜索未完成。');}
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
      document.getElementById('answer').innerHTML = `<p class="live-answer-error" role="alert">${esc(message)}</p>`;
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
  renderAnswer = function(anim) {
    const ds = state.ds;
    if (ds?.live && ds.status === 'insufficient') {
      const suggestion = ds.query.includes('推荐') ? '“推荐”可以指工具、专家或岗位。把推荐对象和使用场景写清楚，有助于找到更相关的资料。' : '补充主题或产品的完整名称、时间和适用地区，有助于找到更相关的资料。';
      document.getElementById('answer').innerHTML = `<div class="surface live-empty"><span class="live-empty-label">资料不足</span><h2>补充一点条件，再继续搜索</h2><p>${esc(ds.diagnostic)}</p><p class="live-note">${esc(suggestion)}</p></div>`;
      return;
    }
    original.renderAnswer(anim);
    if (ds?.live) document.querySelectorAll('#answer .ktag').forEach((tag, i) => tag.textContent = ds.sents[i].f.length > 1 ? '多源引用' : '单源引用');
  };
  live.decoratePop = function(pop, sentence) {
    pop.scrollTop = 0;
    pop.querySelector('.desc').textContent = '这段回答关联的原始选段如下，可打开网页核对上下文。';
    pop.querySelector('.kbadge').textContent = sentence.f.length > 1 ? '多源引用' : '单源引用';
    pop.querySelectorAll('.tsrc').forEach((el, i) => {
      const ref = sentence.f[i], source = state.ds.byId[ref.id];
      el.querySelector('.tsrc-h').innerHTML = `${ico(source)}<span class="live-source-name">${esc(short(source))}</span><span class="scorev">${source.api_score.toFixed(2)} / 3</span>`;
      el.insertAdjacentHTML('beforeend', `<div class="live-evidence-foot"><span>${ref.basis === 'body' ? '网页正文' : '搜索摘要'} · ${esc(ref.evidence_id)}</span><a href="${esc(safeURL(source.url))}" target="_blank" rel="noopener noreferrer">打开原文 ${ARROW}</a></div>`);
    });
  };
  renderSide = function(loading) {
    if (!state.ds?.live) return original.renderSide(loading);
    const ds = state.ds, misses = ds.sources.filter(s => !ds.cited.includes(s.id));
    document.getElementById('side').innerHTML = `<div class="sec-h"><b>来源</b><span>${ds.cited.length} 个引用</span></div><div class="srcs">${ds.cited.map((id, i) => srcCard(ds.byId[id], ds, i)).join('')}</div>${misses.length ? `<div class="xcard"><div class="sec-h"><b>未采用的候选</b><span>${misses.length} 个</span></div><p class="sub">本站选用线 ${Number(ds.quality?.min_score || 1.5).toFixed(2)} / 3，候选与实际引用分别记录。</p>${misses.slice(0, 3).map(s => `<div class="miss"><div class="miss-h"><b title="${esc(s.site)}">${esc(short(s))}</b><span class="gap">${s.api_score.toFixed(2)} / 3</span></div><p>${esc(s.why)}</p></div>`).join('')}<button class="linkbtn press" id="live-candidates">查看全部候选 ${ARROW}</button></div>` : ''}`;
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

  const descriptions = [
    '保留原问题并生成少量等义查询，语言范围在实际搜索词中明确记录。',
    '每组查询调用一次 DeepSeek Search，按实际返回数量汇总并合并重复网址。',
    '采用 API 原始排序分，本站以 1.50 分作为选用线，最多精读 5 个达标来源。',
    '过滤标题、导航与无效短标签，保留正文选段；使用摘要时单独标明依据类型。',
    '资料充足时生成回答并核对引用编号。资料不足时保留检索记录，请用户补充条件。',
    '引用与候选分别记录，每条引用都能追溯到已保存的选段和原始网页。'
  ];
  const guidance = [
    ['把推荐对象、场景和地区写清楚。', '保留原词，避免把工具、岗位和专家混为同一个需求。', '需要外语原文时，可以在问题里明确说明。'],
    ['让网页标题和正文围绕同一个具体问题。', '本次只展示 Search 的实际返回数量。', '搜索语言会影响可召回的资料范围。'],
    ['排序分保留 API 的 0～3 原始刻度。', '选用线是本站规则，权威等级未知时保持未知。', '低分候选会保留在过程页，供人工复核。'],
    ['正文提供完整事实和上下文，减少纯导航内容。', '引用正文与引用搜索摘要分别标记。', '可用段落不足时，补充更具体的查询条件。'],
    ['每段回答关联已存在的证据编号。', '多源引用表示关联多个来源，具体结论可继续核对原文。', '检索证据不足时，先澄清需求。'],
    ['打开引用链接核对上下文。', '未被这次回答引用的来源仍可在候选记录中查看。', '一次查询的引用情况只代表这次运行。']
  ];
  live.stageMeta = index => ({p: descriptions[index], g: guidance[index], t: ['RAG']});
  const lead = text => `<p class="lead">${esc(text)}</p>`;
  const emptyStage = text => `<div class="surface live-stage-empty">${esc(text)}</div>`;
  const liveStages = {
    understand: ds => `<h2>先确认问题，再展开查询</h2>${lead('以下保留原始问题、搜索语言和实际发出的查询，方便核对推荐方向。')}<div class="u-grid"><div class="u-card"><small>识别的意图</small><div class="big">${esc(ds.intent.type || '综合问题')}</div></div><div class="u-card"><small>搜索语言</small><div class="big">${esc(languageLabel(ds))}</div></div><div class="u-card"><small>原始问题</small><div class="big">${esc(ds.query)}</div></div><div class="u-card"><small>本次执行规则</small><dl><dt>查询数量</dt><dd>${ds.searches.length} 组</dd><dt>来源选用线</dt><dd>${Number(ds.quality?.min_score || 1.5).toFixed(2)} / 3</dd></dl></div></div><p class="subh">查询展开 · 原问题与等义查询</p><div class="fan" id="fan"><svg class="wires" id="wires"></svg><div class="fan-q" id="fanq">${esc(ds.query)}</div><ul class="fan-list">${ds.searches.map((s, i) => `<li><span>Q${i + 1}</span>${esc(s.query)}</li>`).join('')}</ul></div>`,
    retrieve: ds => {
      const max = Math.max(1, ...ds.searches.map(s => s.count));
      return `<h2>实际搜索结果汇入候选池</h2>${lead('每条横线表示该查询实际返回的数量，相同网址合并后保留一份。')}<div class="r-legend"><span class="lg"><i style="background:var(--g1)"></i>Search 返回结果</span></div>${ds.searches.map((s, i) => `<div class="r-row"><span class="q" title="${esc(s.query)}"><span>Q${i + 1}</span>${esc(s.query)}</span><div class="bar"><i data-w="${s.count / max * 100}" style="background:var(--g1)"></i></div><span class="n mono">${s.count}</span></div>`).join('')}<div class="sum"><span>原始结果</span><b>${ds.total}</b><i>→</i><span>去重后网页</span><b>${ds.dedup}</b><em>过程页保留排序最高的 ${ds.sources.length} 个候选，实际精读 ${selectedCount(ds)} 个来源。</em></div>`;
    },
    rank: ds => `<h2>按原始排序分选择来源</h2>${lead('排序分采用 0～3 刻度，本站选用线为 1.50。权威等级采用 0～4 刻度，未知值单独标记。')}<div class="cmeta"><span>候选网页 <b>${ds.dedup}</b></span><span>达标来源 <b>${ds.quality?.eligible_count ?? ds.sources.length}</b></span><span>实际精读 <b>${selectedCount(ds)}</b></span></div>${ds.sources.length ? `<div class="lab"><div class="lab-h"><b>本次候选与选用情况</b><span class="live-table-key">API 排序分 / 3</span></div><div class="live-board">${ds.sources.map((s, i) => `<div class="brow"><span class="rk">${i + 1}</span><div class="nm">${ico(s)}<div><a href="${esc(safeURL(s.url))}" target="_blank" rel="noopener noreferrer">${esc(short(s))}</a><small>${esc(s.type)} · 权威 ${s.authority < 0 ? '未知' : s.authority}</small></div></div><span class="scorev">${s.api_score.toFixed(2)}</span><span class="stat"><span class="badge ${s.read ? 'in' : 'out'}">${s.read ? '精读' : s.eligible === false ? '未采用' : '候选'}</span></span></div>`).join('')}</div></div>` : emptyStage('本次查询没有返回可用网页。请补充推荐对象或使用场景。')}`,
    chunk: ds => {
      const ids = [...new Set(ds.evidence.map(e => e.source_id))];
      return `<h2>阅读有内容的段落</h2>${lead('纯标题和导航标签不作为证据。正文与摘要分别记录，下面展示实际进入模型上下文的选段。')}<div class="cmeta"><span>实际精读 <b>${selectedCount(ds)}</b> 页</span><span>进入上下文 <b>${ds.evidence.length}</b> 段</span></div>${ids.length ? ids.map((id, i) => {const source = ds.byId[id]; return `<details class="doc live-doc" ${i === 0 ? 'open' : ''}><summary class="doc-bar"><span class="live-doc-name">${esc(short(source))}</span><span class="u">${esc(safeURL(source.url))}</span><span>${ds.evidence.filter(e => e.source_id === id).length} 段</span></summary><div class="doc-body"><p class="doc-title">${sourceLink(source)}</p>${ds.evidence.filter(e => e.source_id === id).map(e => `<div class="chunk pick"><p><span class="mono live-evidence-id">${esc(e.id)}</span>${esc(e.text)}</p><div class="cs"><span>${e.basis === 'body' ? '网页正文' : '搜索摘要'}</span><span class="ctag">进入上下文</span></div></div>`).join('')}</div></details>`;}).join('') : emptyStage('本次没有找到可进入上下文的有效段落，因此跳过回答生成。')}`;
    },
    generate: ds => {
      const single = ds.sents.filter(s => s.f.length === 1).length, multiple = ds.sents.length - single;
      return `<h2>把选段整理成有依据的回答</h2>${lead(ds.sents.length ? `本次生成 ${ds.sents.length} 段回答，下面展示每段与来源的对应关系。` : '本次资料不足，没有调用回答模型。检索记录完整保留，可以补充条件后继续。')}${ds.sents.length ? `<div class="comp"><i style="width:${single / ds.sents.length * 100}%;background:var(--accent)"></i><i style="width:${multiple / ds.sents.length * 100}%;background:var(--g4)"></i></div><div class="comp-l"><span class="lg"><i style="background:var(--accent)"></i>单源引用 <b>${single}</b></span><span class="lg"><i style="background:var(--g4)"></i>多源引用 <b>${multiple}</b></span></div><div class="map">${ds.sents.map((s, i) => `<div class="mrow"><span class="ix">${String(i + 1).padStart(2, '0')}</span><span class="tx">${esc(s.x)}</span><span class="fr"><span class="tagk ${s.f.length > 1 ? 'merge' : 'extract'}">${s.f.length > 1 ? '多源引用' : '单源引用'}</span>${s.f.map(f => `<span class="chip-s" style="--sc:var(--s${ds.color[f.id]})">${ico(ds.byId[f.id])}${esc(short(ds.byId[f.id]))}</span>`).join('')}</span></div>`).join('')}</div>` : emptyStage(ds.diagnostic || '请补充推荐对象、使用场景或地区。')}`;
    },
    cite: ds => {
      const misses = ds.sources.filter(s => !ds.cited.includes(s.id));
      return `<h2>${ds.cited.length} 个来源获得引用</h2>${lead('实际引用与未采用的候选分别记录，来源链接支持继续核对原文。')}${ds.cited.length ? `<div class="cgrid">${ds.cited.map(id => {const s = ds.byId[id]; return `<div class="ccard" style="--sc:var(--s${ds.color[id]})"><div class="h">${ico(s)}<span>${esc(short(s))}</span><span class="scorev">${s.api_score.toFixed(2)} / 3</span></div><p>关联 <b>${ds.sents.filter(sg => sg.f.some(f => f.id === id)).length}</b> 段回答 · ${esc(s.type)}</p>${sourceLink(s)}</div>`;}).join('')}</div>` : emptyStage('本次没有形成引用。低分或缺少有效段落的候选不会进入回答。')}${misses.length ? `<p class="subh live-section-gap">未采用的候选 · 本次记录</p>${misses.map(s => `<div class="mcard live-miss-card"><div class="h">${ico(s)}<b>${esc(short(s))}</b><span class="gap">${s.api_score.toFixed(2)} / 3</span></div><div><small>本次未引用原因</small><p>${esc(s.why)}</p></div><div><small>候选页面</small><p>${sourceLink(s)}</p></div></div>`).join('')}` : ''}`;
    }
  };
  Object.keys(originalStages).forEach(key => STAGE_R[key] = ds => ds.live ? liveStages[key](ds) : originalStages[key](ds));
  Object.keys(originalAfter).forEach(key => STAGE_AFTER[key] = ds => {
    if (!ds.live || key === 'understand' || key === 'retrieve') return originalAfter[key](ds);
  });
  try {if (sessionStorage.getItem('geo-mode') === 'live') enterLive();} catch (_) {}
})();
