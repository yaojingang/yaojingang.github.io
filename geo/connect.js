/* Personal Key entry runs on a separate page without analytics. */
(() => {
  'use strict';
  const form=document.getElementById('key-form'),input=document.getElementById('api-key'),button=document.getElementById('connect'),error=document.getElementById('key-error');
  const reveal=document.getElementById('reveal');
  let busy=false,revision=0;
  const lock=value=>{busy=value;[input,button,reveal,...['resume-key','replace-key','disconnect','cancel-replace'].map(id=>document.getElementById(id))].forEach(el=>el.disabled=value);};
  input.addEventListener('input',()=>revision++);
  reveal.onclick=()=>{const show=input.type==='password';input.type=show?'text':'password';reveal.textContent=show?'隐藏':'显示';reveal.setAttribute('aria-pressed',String(show));reveal.setAttribute('aria-label',show?'隐藏 API Key':'显示 API Key');};
  const request=async(path,options={})=>{
    const r=await fetch('/geo/api/'+path,{credentials:'same-origin',cache:'no-store',...options});
    const data=await r.json();if(!r.ok)throw new Error(data.error?.message||'连接暂未完成，请稍后再试。');return data;
  };
  form.onsubmit=async event=>{
    event.preventDefault();if(busy)return;revision++;
    let key=input.value.trim();
    if(!/^sk-[A-Za-z0-9_-]{16,200}$/.test(key)){error.textContent='请粘贴完整的 DeepSeek API Key，以 sk- 开头。';return;}
    lock(true);error.textContent='';form.setAttribute('aria-busy','true');button.querySelector('span').textContent='正在验证 Key…';button.querySelector('i').hidden=false;
    try{
      await request('personal-session',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({api_key:key})});
      input.value='';key='';window.location.replace('/geo/?personal=1');
    }catch(e){error.textContent=e.message||'连接暂未完成，请稍后再试。';}
    finally{input.value='';key='';lock(false);if(error.textContent)input.focus();form.removeAttribute('aria-busy');button.querySelector('span').textContent='验证并开始搜索 →';button.querySelector('i').hidden=true;}
  };
  document.getElementById('resume-key').onclick=async()=>{
    if(busy)return;revision++;lock(true);
    try{await request('personal-session/restore',{method:'POST'});window.location.replace('/geo/?personal=1');}
    catch(e){document.getElementById('connected').hidden=true;form.hidden=false;error.textContent=e.message;}
    finally{lock(false);if(!form.hidden)input.focus();}
  };
  document.getElementById('disconnect').onclick=async()=>{
    if(busy)return;revision++;lock(true);
    try{await request('personal-session',{method:'DELETE'});try{sessionStorage.removeItem('geo-provider');sessionStorage.setItem('geo-mode','demo');}catch(_){}document.getElementById('connected').hidden=true;form.hidden=false;input.focus();}
    catch(e){form.hidden=false;error.textContent=e.message;}
    finally{lock(false);if(!form.hidden)input.focus();}
  };
  document.getElementById('replace-key').onclick=()=>{if(busy)return;revision++;document.getElementById('connected').hidden=true;form.hidden=false;document.getElementById('cancel-replace').hidden=false;input.focus();};
  document.getElementById('cancel-replace').onclick=()=>{if(busy)return;revision++;input.value='';error.textContent='';document.getElementById('connected').hidden=false;form.hidden=true;};
  request('status').then(status=>{if(revision===0&&!busy&&!input.value&&(status.saved_key||status.authenticated&&status.access_mode==='personal')){document.getElementById('connected').hidden=false;form.hidden=true;}}).catch(()=>{});
  window.addEventListener('pagehide',()=>{input.value='';});
})();
