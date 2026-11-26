const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const screenEl = $('#screen');
const icon = id => `<svg class="i"><use href="#i-${id}"/></svg>`;

/* ---------- 缩放适配 ---------- */
function fit() {
  const h = $('.design').offsetHeight + 14;
  const s = Math.min((innerWidth - 24) / 1280, (innerHeight - h - 24) / 720);
  const f = $('#fit');
  f.style.width = 1280 * s + 'px';
  f.style.height = 720 * s + 'px';
  screenEl.style.transform = `scale(${s})`;
}
addEventListener('resize', fit);

/* ---------- 路由 ---------- */
const dockMap = { theme: 'apps' };
function go(name) {
  $$('.view').forEach(v => v.classList.toggle('active', v.id === 'v-' + name));
  const d = dockMap[name] || name;
  $$('.nav').forEach(n => n.classList.toggle('active', n.dataset.go === d));
}
$$('.nav').forEach(n => n.onclick = () => go(n.dataset.go));

let toastT;
function toast(msg) {
  const t = $('#toast'); t.textContent = msg; t.classList.add('show');
  clearTimeout(toastT); toastT = setTimeout(() => t.classList.remove('show'), 1600);
}

/* ---------- 地图 (SVG 绘制) ---------- */
const MAP_SVG = `
<svg class="mapsvg" viewBox="0 0 1000 700" preserveAspectRatio="xMidYMid slice">
  <rect class="bg" width="1000" height="700"/>
  <path class="water" d="M0 540 C150 495 270 580 430 555 S720 615 1000 565 V700 H0Z"/>
  <rect class="park" x="610" y="150" width="220" height="95" rx="22"/>
  <rect class="park" x="40" y="440" width="170" height="70" rx="20"/>
  <rect class="park" x="370" y="30" width="120" height="70" rx="18"/>
  <g class="rd" stroke-width="9">
    <path d="M0 120H1000M0 330H1000M0 470H1000M70 0V700M240 0V700M420 0V540M600 0V560M790 0V560M940 0V560"/>
  </g>
  <g class="rc" stroke-width="30"><path d="M-20 640L330 440L640 300L1020 140"/><path d="M510 -20L560 300L650 560"/></g>
  <g class="rm" stroke-width="24"><path d="M-20 640L330 440L640 300L1020 140"/><path d="M510 -20L560 300L650 560"/></g>
  <path class="routec" d="M240 700V330H420V230H790V120H940"/>
  <path class="route" d="M240 700V330H420V230H790V120H940"/>
  <text x="90" y="112">Maple Ave</text><text x="640" y="322">Harbor Blvd</text><text x="258" y="462">Pine St</text>
  <text x="640" y="190">Central Park</text><text x="410" y="52">Museum</text>
  <g transform="translate(240 520)">
    <circle class="pulse" r="26"/>
    <circle r="17" fill="#fff"/>
    <path d="M0 -10L8 9L0 5L-8 9Z" fill="var(--accent)" stroke="var(--accent)" stroke-width="2" stroke-linejoin="round"/>
  </g>
  <g transform="translate(940 120)">
    <circle r="14" fill="#ff453a"/><circle r="5.5" fill="#fff"/>
  </g>
</svg>
<div class="mapui">
  <div class="turn glass"><div class="ar">${icon('turn')}</div><div><div class="d">300 米</div><div class="s">右转 · 进入 Harbor Blvd</div></div></div>
  <div class="mapbot">
    <div class="eta glass"><div><div class="big">18 分钟</div><div class="sm">9.4 公里 · 15:32 到达</div></div><button class="go">结束</button></div>
    <div class="zoom glass"><button>+</button><button>−</button></div>
  </div>
</div>`;

/* ---------- 卡片 (音乐 / 天气) ---------- */
const CARDS = `
<div class="card glass mcard" data-go-music>
  <div class="artw"><div class="art m-art"></div></div>
  <div><div class="ttl m-title"></div><div class="sub m-artist"></div></div>
  <div class="bar"><i class="m-bar"></i></div>
  <div class="ctl">
    <button data-act="prev">${icon('prev')}</button>
    <button class="pp" data-act="pp"><svg class="i"><use class="m-play" href="#i-pause"/></svg></button>
    <button data-act="next">${icon('next')}</button>
  </div>
</div>
<div class="card glass wcard">
  <div class="city">${icon('map').replace('class="i"', 'class="i" style="width:15px;height:15px;color:#fff"')}上海</div>
  <div class="wrow"><div><div class="t">24°</div><div class="d">晴 · 27° / 18°</div></div>${icon('sun')}</div>
</div>`;

$$('[data-map]').forEach(m => m.innerHTML = MAP_SVG);
$$('[data-cards]').forEach(c => c.innerHTML = CARDS);

/* ---------- 音乐 ---------- */
const tracks = [
  { t: '夜空中最亮的星', a: '逃跑计划', d: 252, g: ['#5e5ce6', '#ff375f'] },
  { t: 'Blinding Lights', a: 'The Weeknd', d: 200, g: ['#ff453a', '#ff9f0a'] },
  { t: '晴天', a: '周杰伦', d: 269, g: ['#32d74b', '#0a84ff'] },
  { t: 'Midnight City', a: 'M83', d: 244, g: ['#bf5af2', '#0a84ff'] },
  { t: 'Golden Hour', a: 'JVKE', d: 209, g: ['#ffd60a', '#ff453a'] },
];
let cur = 0, pos = 37, playing = true;
const fmt = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
const grad = g => `linear-gradient(135deg,${g[0]},${g[1]})`;

function renderMusic() {
  const tr = tracks[cur];
  $$('.m-title').forEach(e => e.textContent = tr.t);
  $$('.m-artist').forEach(e => e.textContent = tr.a);
  $$('.m-art').forEach(e => e.style.background = `radial-gradient(circle at 30% 25%,rgba(255,255,255,.45),transparent 45%),${grad(tr.g)}`);
  $$('.m-dur').forEach(e => e.textContent = fmt(tr.d));
  $$('.m-play').forEach(e => e.setAttribute('href', playing ? '#i-pause' : '#i-play'));
  $$('.q').forEach((q, i) => q.classList.toggle('on', i === cur));
  tickMusic();
}
function tickMusic() {
  const tr = tracks[cur];
  $$('.m-bar').forEach(e => e.style.width = (pos / tr.d * 100) + '%');
  $$('.m-cur').forEach(e => e.textContent = fmt(pos));
}
function setTrack(i) { cur = (i + tracks.length) % tracks.length; pos = 0; renderMusic(); }
document.addEventListener('click', e => {
  const b = e.target.closest('[data-act]');
  if (b) {
    e.stopPropagation();
    if (b.dataset.act === 'pp') { playing = !playing; renderMusic(); }
    else setTrack(cur + (b.dataset.act === 'next' ? 1 : -1));
    return;
  }
  if (e.target.closest('[data-go-music]')) go('music');
});
setInterval(() => { if (!playing) return; pos++; if (pos >= tracks[cur].d) setTrack(cur + 1); else tickMusic(); }, 1000);

$('#queue').innerHTML = tracks.map((t, i) => `
  <button class="q" data-i="${i}"><div class="th" style="background:${grad(t.g)}"></div>
  <div class="tx"><div>${t.t}</div><div class="tm">${t.a}</div></div><div class="tm">${fmt(t.d)}</div></button>`).join('');
$$('.q').forEach(q => q.onclick = () => { playing = true; setTrack(+q.dataset.i); });
renderMusic();

/* ---------- 应用列表 ---------- */
const pinned = [
  { n: '车机主页', i: 'car', c: ['#0a84ff', '#5e5ce6'], go: 'home' },
  { n: '设置', i: 'gear', c: ['#8e8e93', '#48484a'], go: 'settings' },
  { n: '主题', i: 'theme', c: ['#ff375f', '#bf5af2'], go: 'theme' },
];
const others = [
  { n: '电话', i: 'phone', c: ['#32d74b', '#248a3d'] },
  { n: '信息', i: 'msg', c: ['#64d2ff', '#0a84ff'] },
  { n: '地图', i: 'map', c: ['#30d158', '#0a84ff'], go: 'map' },
  { n: '音乐', i: 'music', c: ['#ff453a', '#ff2d55'], go: 'music' },
  { n: '日历', i: 'cal', c: ['#ff6961', '#ff3b30'] },
  { n: '播客', i: 'mic', c: ['#bf5af2', '#8944ab'] },
  { n: '图书', i: 'book', c: ['#ff9f0a', '#ff6a00'] },
  { n: '天气', i: 'cloud', c: ['#64d2ff', '#3a7bd5'] },
  { n: '蓝牙', i: 'bt', c: ['#0a84ff', '#0040dd'] },
  { n: '无线网络', i: 'wifi', c: ['#5ac8fa', '#007aff'] },
  { n: '亮度', i: 'sun', c: ['#ffd60a', '#ff9f0a'] },
  { n: '分屏', i: 'split', c: ['#5e5ce6', '#3634a3'], go: 'split' },
];
const appHTML = (a, pin) => `
  <button class="app" data-app="${a.n}"><div class="lg" style="background:linear-gradient(160deg,${a.c[0]},${a.c[1]})">${icon(a.i)}${pin ? '<span class="pin">★</span>' : ''}</div><div class="nm">${a.n}</div></button>`;
$('#appsPinned').innerHTML = pinned.map(a => appHTML(a, true)).join('');
$('#appsOther').innerHTML = others.map(a => appHTML(a)).join('');
$$('.app').forEach(el => el.onclick = () => {
  const a = [...pinned, ...others].find(x => x.n === el.dataset.app);
  a.go ? go(a.go) : toast(`已打开「${a.n}」`);
});

/* ---------- 主题 / 外观 / 分屏比例 ---------- */
const walls = [
  { n: '极光', v: `radial-gradient(900px 600px at 15% 10%,#3a2bd6 0%,transparent 60%),radial-gradient(800px 600px at 90% 20%,#d6336c 0%,transparent 55%),radial-gradient(900px 700px at 60% 100%,#0e9aa7 0%,transparent 60%),#10101c` },
  { n: '日落', v: `radial-gradient(900px 600px at 80% 10%,#ff9f0a 0%,transparent 60%),radial-gradient(900px 600px at 10% 90%,#ff375f 0%,transparent 60%),#2b1033` },
  { n: '森林', v: `radial-gradient(900px 600px at 20% 15%,#30d158 0%,transparent 55%),radial-gradient(900px 700px at 90% 90%,#0a6f8f 0%,transparent 60%),#0b1f1a` },
  { n: '深海', v: `radial-gradient(900px 600px at 70% 10%,#0a84ff 0%,transparent 55%),radial-gradient(900px 700px at 10% 100%,#5e5ce6 0%,transparent 60%),#06102a` },
  { n: '石墨', v: `radial-gradient(900px 600px at 30% 0%,#4a4a55 0%,transparent 60%),#16161a` },
];
const accents = ['#0a84ff', '#30d158', '#ff9f0a', '#ff375f', '#bf5af2', '#64d2ff'];
let wallIdx = 0, accent = accents[0], mode = 'dark', mapRatio = 3, musicRatio = 2, projectionFps = 30;

function applyTheme() {
  screenEl.classList.toggle('light', mode === 'light');
  screenEl.style.setProperty('--accent', accent);
  screenEl.style.setProperty('--wall', mode === 'light'
    ? `linear-gradient(rgba(255,255,255,.42),rgba(255,255,255,.42)),${walls[wallIdx].v}` : walls[wallIdx].v);
  screenEl.style.setProperty('--split', `${mapRatio}fr ${musicRatio}fr`);
  $$('[data-modeseg] button,#modeSeg button').forEach(b => b.classList.toggle('on', b.dataset.m === mode));
  $$('[data-split-ratio="map"]').forEach(input => { if (document.activeElement !== input) input.value = mapRatio; });
  $$('[data-split-ratio="music"]').forEach(input => { if (document.activeElement !== input) input.value = musicRatio; });
  $$('#projectionFps button').forEach(button => button.classList.toggle('on', Number(button.dataset.fps) === projectionFps));
  $$('[data-walls] .wall').forEach(w => w.classList.toggle('on', +w.dataset.i === wallIdx));
  $$('[data-accents] button').forEach(b => b.classList.toggle('on', b.dataset.c === accent));
}
$$('[data-walls]').forEach(c => c.innerHTML = walls.map((w, i) =>
  `<button class="wall" data-i="${i}" style="background:${w.v.replace(/\d+px \d+px/g, '90% 90%')}"><span>${w.n}</span></button>`).join(''));
$$('[data-accents]').forEach(c => c.innerHTML = accents.map(a => `<button data-c="${a}" style="background:${a}"></button>`).join(''));
document.addEventListener('click', e => {
  const t = e.target.closest('button'); if (!t) return;
  if (t.dataset.m) mode = t.dataset.m;
  else if (t.dataset.splitStep) {
    const [pane, step] = t.dataset.splitStep.split(':');
    const current = pane === 'map' ? mapRatio : musicRatio;
    const next = Math.max(1, Math.min(10, current + Number(step)));
    if (pane === 'map') mapRatio = next;
    else musicRatio = next;
  }
  else if (t.dataset.fps) projectionFps = Number(t.dataset.fps);
  else if (t.classList.contains('wall')) wallIdx = +t.dataset.i;
  else if (t.dataset.c) accent = t.dataset.c;
  else return;
  applyTheme();
});
$$('[data-split-ratio]').forEach(input => input.addEventListener('change', () => {
  const pane = input.dataset.splitRatio;
  const value = Number(input.value);
  if (!Number.isInteger(value) || value < 1 || value > 10) {
    input.value = pane === 'map' ? mapRatio : musicRatio;
    return;
  }
  if (pane === 'map') mapRatio = value;
  else if (pane === 'music') musicRatio = value;
  applyTheme();
}));
applyTheme();

/* ---------- 设置 ---------- */
$$('.si').forEach(b => b.onclick = () => {
  $$('.si').forEach(x => x.classList.toggle('on', x === b));
  $$('.sp').forEach(p => p.classList.toggle('on', p.id === 'tab-' + b.dataset.tab));
});
$$('.tg').forEach(t => t.onclick = () => t.classList.toggle('on'));
$('#brightness').oninput = e => screenEl.style.filter = `brightness(${0.5 + e.target.value / 200})`;
$('#fontSeg').onclick = e => {
  const b = e.target.closest('button'); if (!b) return;
  $$('#fontSeg button').forEach(x => x.classList.toggle('on', x === b));
  $$('.sr,.panel').forEach(p => p.style.zoom = b.dataset.f);
};

fit();
if (location.hash.length > 1) go(location.hash.slice(1));
