/* GEO internal search: authenticated requests and recorded evidence. */
(() => {
  'use strict';
  const api = '/geo/api';
  const modeButton = document.getElementById('beta-mode');
  const meter = document.getElementById('live-status');
  const tests = document.getElementById('live-tests');
  const original = {search, renderSide, renderThink, renderPipe, renderAnswer, renderLegend, openPop};
  const originalStages = {...STAGE_R};
  const originalAfter = {...STAGE_AFTER};
  const live = window.GeoLive = {active: false, controller: null, generation: 0, events: [], budget: null};
  const money = value => Number(value || 0).toFixed(3);
  const safeURL = value => {
    try {const url = new URL(value); return ['https:', 'http:'].includes(url.protocol) ? url.href : '#';}
    catch (_) {return '#';}
  };
  const sourceLink = s => `<a href="${esc(safeURL(s.url))}" target="_blank" rel="noopener noreferrer">${esc(s.title || s.site)}</a>`;
  const note = text => `<p class="live-note">${esc(text)}</p>`;
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

  function progress() {
    const rows = live.events.map(item => `<li>${esc(item.message)}</li>`).join('');
    document.getElementById('think').className = 'think running';
    document.getElementById('think').innerHTML = `<span class="shimmer">正在联网整理资料…</span><ol class="live-log" aria-live="polite">${rows}</ol><button class="live-cancel" type="button" id="live-cancel">停止本次搜索</button>`;
    document.getElementById('live-cancel').onclick = () => live.controller?.abort();
  }
  function prepare(data) {
    if (!data.live || !Array.isArray(data.sources) || !Array.isArray(data.answer) || !Array.isArray(data.cited)) throw new Error('内测返回的数据格式有误。');
    data.byId = Object.fromEntries(data.sources.map(source => [source.id, source]));
    if (data.cited.some(id => !data.byId[id])) throw new Error('来源对应关系不完整。');
    data.rank = data.sources.map(s => ({s, v: s.api_score}));
    data.color = {};
    data.sources.forEach((s, i) => data.color[s.id] = (i % 5) + 1);
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
          const hints = [`本次实际联网结果 · ${data.elapsed_seconds} 秒 · ${new Date(data.created_at).toLocaleString('zh-CN')}`, ...(data.cached ? ['读取 15 分钟内的相同问题缓存，本次没有新增 API 调用。'] : []), ...(data.warnings || [])];
          document.getElementById('r-banner').innerHTML = hints.map(note).join('') + note(statusLabel());
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
    if (!state.ds?.live) return original.renderLegend();
    const ds = state.ds;
    document.getElementById('legend').innerHTML = `<span class="lt">关联来源</span>${ds.cited.map(id => `<span class="lg"><i style="background:var(--s${ds.color[id]})"></i>${esc(ds.byId[id].site)}</span>`).join('')}<span class="lt">点击回答片段核对证据</span>`;
  };
  renderAnswer = function(anim) {
    original.renderAnswer(anim);
    if (state.ds?.live) document.querySelectorAll('#answer .ktag').forEach((tag, i) => tag.textContent = state.ds.sents[i].f.length > 1 ? '多源引用' : '单源引用');
  };
  openPop = function(element) {
    original.openPop(element);
    if (!state.ds?.live) return;
    document.querySelector('#pop .desc').textContent = '下方展示这段回答关联的原始选段。请结合页面上下文核对结论。';
    document.querySelector('#pop .kbadge').textContent = '证据关联';
    document.querySelectorAll('#pop .tsrc').forEach((el, i) => {
      const ref = state.ds.sents[Number(element.dataset.i)].f[i];
      el.insertAdjacentHTML('beforeend', note(ref.basis === 'body' ? '依据：网页正文选段' : '依据：搜索服务返回的摘要') + sourceLink(state.ds.byId[ref.id]));
    });
  };
  renderSide = function(loading) {
    if (!state.ds?.live) return original.renderSide(loading);
    const ds = state.ds;
    document.getElementById('side').innerHTML = `<div class="sec-h"><b>本次引用来源</b><span>${ds.cited.length} 个</span></div>${ds.cited.map(id => {
      const s = ds.byId[id];
      return `<div class="live-source src" data-id="${esc(s.id)}"><div class="src-site">${ico(s)}${esc(s.site)}</div>${sourceLink(s)}${note(`${s.type} · API 排序分 ${s.api_score.toFixed(2)}/3 · ${s.date}`)}</div>`;
    }).join('')}${note('点击正文中的引用，可核对原始选段。API 排序分与本次引用次数分别记录。')}`;
  };
  renderThink = function(open) {
    if (!state.ds?.live) return original.renderThink(open);
    document.getElementById('think').className = 'think';
    document.getElementById('think').innerHTML = `<details class="live-detail" ${open ? 'open' : ''}><summary>查看本次实际执行记录</summary><ol class="live-log">${state.ds.trace.map(e => `<li>${esc(e.message)}</li>`).join('')}</ol></details>`;
  };
  renderPipe = function() {
    if (!state.ds?.live) return original.renderPipe();
    const ds = state.ds;
    const counts = [ds.searches.length, ds.dedup, Math.min(ds.sources.length, 5), ds.evidence.length, ds.sents.length, ds.cited.length];
    document.getElementById('pipe').innerHTML = `<div class="pipe"><div class="pipe-h"><b>本次搜索与证据记录</b></div><div class="pipe-steps">${STAGES.map((stage, i) => `<button class="pstep press" data-live-stage="${i}" type="button"><small>0${i + 1} ${stage.n}</small><strong>${counts[i]}</strong><span>${['个搜索词', '个候选网页', '个重点来源', '段输入证据', '段回答', '个引用来源'][i]}</span></button>`).join('')}</div></div>`;
    document.querySelectorAll('[data-live-stage]').forEach(button => button.onclick = () => openProcess(Number(button.dataset.liveStage)));
  };

  const descriptions = [
    '本站模型根据原始问题生成最多三个搜索词，以下列出实际发出的查询。',
    '每个搜索词调用一次 DeepSeek Search。结果数量按接口实际返回计算，相同网址会合并。',
    '排序分与权威等级由 DeepSeek Search 返回。界面保留原始刻度和未知值，便于复核。',
    '本站从重点来源的正文或摘要中选取相关段落，并保留来源与内容类型。词项匹配用于本站选段。',
    '模型依据这些选段生成回答。服务端核对证据编号，并将原始选段与回答关联。',
    '本次回答中的引用来自已记录的选段。每份引用都可以打开对应网页，继续核对上下文。'
  ];
  live.stageMeta = index => ({p: descriptions[index], g: ['核对原始网页和发布时间。', '区分网页正文、搜索摘要与模型生成的结论。', '根据这次实际查询和引用，检查内容是否回答了具体问题。'], t: ['RAG']});
  const liveStages = {
    understand: ds => `<h2>本次搜索计划</h2>${note(`问题类型：${ds.intent.type || '综合问题'}`)}<ol class="live-log">${ds.searches.map(s => `<li>${esc(s.query)}</li>`).join('')}</ol>${note('这些搜索词由本站模型生成，记录用于解释本次查询。')}`,
    retrieve: ds => `<h2>实际返回的搜索结果</h2><table class="live-table"><thead><tr><th>搜索词</th><th>返回条数</th></tr></thead><tbody>${ds.searches.map(s => `<tr><td>${esc(s.query)}</td><td>${s.count}</td></tr>`).join('')}</tbody></table>${note(`共收到 ${ds.total} 条结果，去重后 ${ds.dedup} 个可用网页。界面保留排序最高的 ${ds.sources.length} 个候选来源。`)}`,
    rank: ds => `<h2>按搜索服务排序分选择来源</h2>${note('排序分采用 0～3 原始刻度；权威等级采用 0～4 原始刻度，未知值单独标注。')}<table class="live-table"><thead><tr><th>来源</th><th>排序分</th><th>权威</th></tr></thead><tbody>${ds.sources.map(s => `<tr><td>${sourceLink(s)}<small>${esc(s.site)}</small></td><td>${s.api_score.toFixed(2)}</td><td>${s.authority < 0 ? '未知' : s.authority}</td></tr>`).join('')}</tbody></table>`,
    chunk: ds => `<h2>进入模型上下文的选段</h2>${note(`共 ${ds.evidence.length} 段资料。每段保留原始文本，摘要来源会单独标注。`)}${ds.evidence.map(e => `<article class="live-evidence"><strong>${esc(e.id)} · ${e.basis === 'body' ? '网页正文' : '搜索摘要'}</strong><p>${esc(e.text)}</p>${sourceLink(ds.byId[e.source_id])}</article>`).join('')}`,
    generate: ds => `<h2>回答与证据的对应关系</h2>${note('引用关系由本站生成流程记录，具体结论可以结合原文复核。')}<div class="map">${ds.sents.map((s, i) => `<div class="mrow"><span class="ix">${String(i + 1).padStart(2, '0')}</span><span class="tx">${esc(s.x)}</span><span class="fr"><span class="tagk ${s.f.length > 1 ? 'merge' : 'extract'}">${s.f.length > 1 ? '多源引用' : '单源引用'}</span>${s.f.map(f => `<span class="chip-s">${esc(ds.byId[f.id].site)}</span>`).join('')}</span></div>`).join('')}</div>`,
    cite: ds => `<h2>本次引用了 ${ds.cited.length} 个来源</h2>${ds.cited.map(id => {const s = ds.byId[id]; return `<article class="live-evidence">${sourceLink(s)}${note(`${s.site} · ${s.type} · ${s.date}`)}${note(`关联 ${ds.sents.filter(sg => sg.f.some(f => f.id === id)).length} 段回答。`)}</article>`;}).join('')}${note('没有出现在回答中的候选来源，只记录为本次未引用。')}`
  };
  Object.keys(originalStages).forEach(key => STAGE_R[key] = ds => ds.live ? liveStages[key](ds) : originalStages[key](ds));
  Object.keys(originalAfter).forEach(key => STAGE_AFTER[key] = ds => {if (!ds.live) return originalAfter[key](ds);});
  try {if (sessionStorage.getItem('geo-mode') === 'live') enterLive();} catch (_) {}
})();
