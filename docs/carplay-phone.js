const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const phone = $('#phone');
const ic = id => `<svg class="i"><use href="#i-${id}"/></svg>`;

/* 适配窗口 */
function fit() {
  const s = Math.min((innerWidth - 40) / 390, (innerHeight - 40) / 844, 1.15);
  $('#fit').style.width = 390 * s + 'px';
  $('#fit').style.height = 844 * s + 'px';
  phone.style.transform = `scale(${s})`;
}
addEventListener('resize', fit); fit();

setInterval(() => { const d = new Date(); $('#clock').textContent = d.getHours() + ':' + String(d.getMinutes()).padStart(2, '0'); }, 1000);
(() => { const d = new Date(); $('#clock').textContent = d.getHours() + ':' + String(d.getMinutes()).padStart(2, '0'); })();

/* 状态机: off(关闭) → waiting(开启·等待连接) → connected(已连接)
   按钮文字: 开启 / 关闭 / 断开连接 */
const S = {
  off:       { text: '已关闭',  sub: '',                 btn: '开启',     hint: '点击按钮开启 CarPlay 服务' },
  waiting:   { text: '已开启',  sub: '等待连接车机…',     btn: '关闭',     hint: '请确认车机蓝牙 / Wi-Fi 已开启，靠近车辆后将自动连接' },
  connected: { text: '已开启',  sub: '已连接到 My Car',   btn: '断开连接', hint: '' },
};
let state = 'off', autoT, durT, sec = 0;
let autoOn = true;
const auto = () => autoOn;

function setState(s) {
  state = s; phone.dataset.s = s;
  const c = S[s];
  $('#stText').textContent = c.text;
  $('#stSub').textContent = c.sub;
  $('#bigText').textContent = c.btn;
  $('#hint').textContent = c.hint;
  clearTimeout(autoT); clearInterval(durT);
  if (s === 'waiting' && auto()) autoT = setTimeout(() => setState('connected'), 4000); // 模拟车机自动连入
  if (s === 'connected') {
    sec = 0; $('#dur').textContent = '00:00';
    durT = setInterval(() => { sec++; $('#dur').textContent = `${String(Math.floor(sec / 60)).padStart(2, '0')}:${String(sec % 60).padStart(2, '0')}`; }, 1000);
    toast('已连接到 My Car');
  }
}
$('#big').onclick = () => {
  if (state === 'off') setState('waiting');
  else if (state === 'waiting') setState('off');
  else { setState('waiting'); toast('已断开连接'); }
};
// 等待连接时，点击提示文字可手动模拟车机连入
$('#hint').onclick = () => { if (state === 'waiting') setState('connected'); };
setState('off');

let toastT;
function toast(m) { const t = $('#toast'); t.textContent = m; t.classList.add('show'); clearTimeout(toastT); toastT = setTimeout(() => t.classList.remove('show'), 1800); }

/* 下拉菜单 */
const menu = $('#dropMenu');
$('#moreBtn').onclick = e => { e.stopPropagation(); menu.classList.toggle('open'); };
phone.addEventListener('click', e => { if (!e.target.closest('#dropMenu')) menu.classList.remove('open'); });

/* 页面: 设置 / 帮助 / 关于 */
const tg = (id, on, t, s = '') => `<div class="item"><div>${t}${s ? `<small>${s}</small>` : ''}</div><div class="tg ${on ? 'on' : ''}" ${id ? `id="${id}"` : ''}></div></div>`;
const PAGES = {
  settings: { t: '设置', h: `
    <div class="grp" id="grpA">
      ${tg('autoConn', true, '自动连接', '检测到车机后自动建立连接')}
      ${tg('', true, '无线 CarPlay', '通过蓝牙 + Wi-Fi 连接')}
      ${tg('', false, '开机自启动')}
    </div>
    <div class="grp">
      ${tg('', true, '连接通知')}
      ${tg('', true, '连接时保持屏幕常亮')}
    </div>
    <div class="grp"><div class="item"><span>已配对车辆</span><span style="color:rgba(255,255,255,.55)">My Car</span></div></div>` },
  help: { t: '帮助', h: `
    <div class="grp">
      <button class="faq">无法连接车机怎么办？<p>请确认手机蓝牙与 Wi-Fi 已开启，车机处于无线 CarPlay 配对模式，并重新点击「开启」。</p></button>
      <button class="faq">如何断开连接？<p>已连接时点击中间的圆形按钮「断开连接」即可，服务仍保持开启状态。</p></button>
      <button class="faq">如何完全关闭服务？<p>在「等待连接」状态下点击「关闭」按钮。</p></button>
      <button class="faq">连接后手机还能使用吗？<p>可以，手机可继续正常使用，通话与导航将同步显示在车机端。</p></button>
    </div>` },
  about: { t: '关于', h: `
    <div class="about"><div class="lg">${ic('car')}</div><h3>CarPlayer</h3><p>版本 1.0.0 (100)</p></div>
    <div class="grp"><div class="item"><span>隐私政策</span><span>›</span></div><div class="item"><span>用户协议</span><span>›</span></div><div class="item"><span>开源许可</span><span>›</span></div></div>` },
};
const sheet = $('#sheet'), panel = $('#panel');
function openPage(k) {
  const p = PAGES[k]; menu.classList.remove('open');
  panel.innerHTML = `<div class="top"><h2>${p.t}</h2><button class="x" id="closeP">${ic('x')}</button></div>${p.h}`;
  sheet.classList.add('open');
  $('#closeP').onclick = () => sheet.classList.remove('open');
  $$('.tg', panel).forEach(t => t.onclick = () => t.classList.toggle('on'));
  const ac = $('#autoConn', panel);
  if (ac) { ac.classList.toggle('on', autoOn); ac.onclick = () => { autoOn = ac.classList.toggle('on'); }; }
  $$('.faq', panel).forEach(f => f.onclick = () => f.classList.toggle('open'));
}
$$('#dropMenu button').forEach(b => b.onclick = () => openPage(b.dataset.page));
sheet.onclick = e => { if (e.target === sheet) sheet.classList.remove('open'); };

// 调试: carplay-phone.html#waiting / #connected / #menu / #settings / #help / #about
const h = location.hash.slice(1);
if (S[h]) setState(h); else if (PAGES[h]) openPage(h); else if (h === 'menu') menu.classList.add('open');
