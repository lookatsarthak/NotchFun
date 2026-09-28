// NotchFun — site behaviour.
//
// One idea runs through the page: the black shape pinned to the top of the window is
// the product. Each chapter drives it the way the real app would, so reading the page
// is watching the notch work. anime.js does the choreography (the hello, bursts, the
// disk-image drag); CSS springs, sampled from the app's own, move the notch itself.

import { animate, createTimeline, createDrawable, stagger } from 'https://cdn.jsdelivr.net/npm/animejs@4.5.0/dist/bundles/anime.esm.min.js';

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
const REPO = 'lookatsarthak/NotchFun';

const notch = $('#notch');
const body = document.body;

// ------------------------------------------------------------------ notch state

// What the notch shows is decided in one place, by priority, the way the app layers
// its own states: a greeting, then a momentary popup, then whatever the current
// chapter asks for, then a hover, then music in the closed notch.
const N = {
  hello: false,
  transient: null,      // { state: 'hud' | 'banner' }
  chapterView: null,    // 'home' | 'shelf' | 'clip' | 'mirror'
  chapterBanner: null,  // a banner held while a chapter shows it
  dragView: null,       // a file being dragged opens the shelf
  preview: false,       // the width slider
  hover: false,
  playing: false,
};
const viewOrder = { home: 0, shelf: 1, clip: 2, mirror: 3 };
let bannerContent = null;

function render() {
  let state = 'closed';
  let view = notch.dataset.view;
  if (N.hello) state = 'hello';
  else if (N.transient) state = N.transient.state;
  else if (N.dragView) { state = 'open'; view = N.dragView; }
  else if (N.chapterView) { state = 'open'; view = N.chapterView; }
  else if (N.chapterBanner) { state = 'banner'; setBanner(N.chapterBanner); }
  else if (N.preview || N.hover) { state = 'open'; view = view === 'mirror' ? 'home' : view; }
  else if (N.playing) state = 'live';

  if (view !== notch.dataset.view) {
    // New content slides in from the side the tab sits on, as in the app.
    const dir = (viewOrder[view] ?? 0) >= (viewOrder[notch.dataset.view] ?? 0) ? 1 : -1;
    notch.style.setProperty('--dir', dir);
    notch.dataset.view = view;
  }
  if (state === 'banner' && N.transient?.banner) setBanner(N.transient.banner);
  notch.dataset.state = state;
  syncLoupes(state);
}

// The magnified copies only ever show closed states; open ones stay at the top.
function syncLoupes(state) {
  const closed = ['closed', 'live', 'hud', 'banner'].includes(state) ? state : (N.playing ? 'live' : 'closed');
  const widths = { closed: 190, live: 270, hud: 330, banner: 380 };
  for (const l of $$('.loupe')) {
    l.dataset.state = closed;
    // As large as the card allows, up to twice the real size.
    const room = l.parentElement.clientWidth - 48;
    const scale = Math.min(2, room / widths[closed]).toFixed(3);
    l.style.cssText = notch.style.cssText.replace(/--ns:[^;]+;?/, '') + `--ls:${scale};`;
    $('.banner-lead', l).innerHTML = $('.banner-lead', notch).innerHTML;
    $('.banner-trail', l).innerHTML = $('.banner-trail', notch).innerHTML;
    $('.hud-icon use', l).setAttribute('href', $('.hud-icon use', notch).getAttribute('href'));
  }
}

function setBanner(b) {
  if (bannerContent === b) return;
  bannerContent = b;
  $('.banner-lead', notch).innerHTML = b.lead;
  $('.banner-trail', notch).innerHTML = b.trail;
}

let transientTimer;
function flash(t, ms = 1500) {
  N.transient = t;
  render();
  clearTimeout(transientTimer);
  transientTimer = setTimeout(() => { N.transient = null; render(); }, ms);
}

// Hovering the page's notch opens it, like the app's "open on hover".
let hoverTimer;
notch.addEventListener('pointerenter', () => { clearTimeout(hoverTimer); N.hover = true; render(); });
notch.addEventListener('pointerleave', () => { hoverTimer = setTimeout(() => { N.hover = false; render(); }, 180); });

// On narrow screens the open notch is scaled to fit rather than clipped.
function fitNotch() {
  const openW = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--open-w')) || 640;
  document.documentElement.style.setProperty('--ns', Math.min(1, (document.documentElement.clientWidth - 20) / openW).toFixed(3));
}
addEventListener('resize', fitNotch);
fitNotch();

// ------------------------------------------------------------------ hello

// The first thing the app does on a new Mac: open the notch and write "hello" in it.
// The page does the same, with the app's own path.
function playHello() {
  const lookUp = $('.look-up');
  if (reduced) return Promise.resolve();
  N.hello = true;
  render();
  const [drawable] = createDrawable('.hello-path');
  drawable.setAttribute('draw', '0 0');
  animate(lookUp, { opacity: [0, 1], translateY: [8, 0], duration: 500, delay: 300, ease: 'out(3)' });
  animate('.look-up .arrow', { translateY: [0, -6, 0], duration: 700, delay: 700, loop: 2, ease: 'inOut(2)' });
  return new Promise(resolve => {
    animate(drawable, {
      draw: ['0 0', '0 1'],
      duration: 2800,
      delay: 450,
      ease: 'inOut(1.6)',
      onComplete: () => setTimeout(() => {
        N.hello = false;
        render();
        animate(lookUp, { opacity: 0, duration: 400 });
        resolve();
      }, 350),
    });
  });
}

// ------------------------------------------------------------------ reveals

// Headings rise line by line; everything else fades up in reading order.
function setupReveals() {
  $$('.reveal-lines, .headline').forEach(h => $$('.line', h).forEach((l, i) => l.style.setProperty('--l', i)));
  const groups = new Map();
  $$('.reveal').forEach(el => {
    const p = el.parentElement;
    const n = groups.get(p) ?? 0;
    el.style.setProperty('--i', n);
    groups.set(p, n + 1);
  });
  const io = new IntersectionObserver(entries => {
    for (const e of entries) if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
  }, { rootMargin: '0px 0px -12% 0px' });
  $$('.reveal, .reveal-lines').forEach(el => io.observe(el));
}

function introHero() {
  const lines = $$('.headline .line > span');
  if (reduced) { lines.forEach(l => (l.style.transform = 'none')); return; }
  animate(lines, { translateY: ['105%', '0%'], duration: 1100, delay: stagger(110, { start: 500 }), ease: 'out(4)' });
}

// ------------------------------------------------------------------ stars

// The night sky from the disk image window, drifting slightly with the pointer.
function starfield() {
  const canvas = $('.stars');
  const ctx = canvas.getContext('2d');
  let w, h, pts = [], mx = 0, my = 0, visible = true, raf;
  const dpr = Math.min(devicePixelRatio || 1, 2);
  function size() {
    w = canvas.clientWidth; h = canvas.clientHeight;
    canvas.width = w * dpr; canvas.height = h * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const count = Math.round((w * h) / 9000);
    pts = Array.from({ length: count }, () => ({
      x: Math.random() * w, y: Math.random() * h, r: Math.random() * 1.2 + 0.2,
      z: Math.random() * 0.8 + 0.2, t: Math.random() * Math.PI * 2, s: Math.random() * 0.015 + 0.004,
    }));
  }
  function frame() {
    ctx.clearRect(0, 0, w, h);
    for (const p of pts) {
      p.t += p.s;
      const a = 0.35 + Math.sin(p.t) * 0.3;
      ctx.globalAlpha = Math.max(0.05, a) * p.z;
      ctx.fillStyle = '#fff';
      ctx.beginPath();
      ctx.arc(p.x + mx * p.z * 14, p.y + my * p.z * 10, p.r, 0, Math.PI * 2);
      ctx.fill();
    }
    if (visible && !reduced) raf = requestAnimationFrame(frame);
  }
  size();
  addEventListener('resize', size);
  addEventListener('pointermove', e => { mx = e.clientX / innerWidth - 0.5; my = e.clientY / innerHeight - 0.5; }, { passive: true });
  new IntersectionObserver(([e]) => {
    visible = e.isIntersecting;
    cancelAnimationFrame(raf);
    if (visible) frame();
  }).observe(canvas);
  frame();
}

// ------------------------------------------------------------------ music

const tracks = [
  { title: 'Night Drive', artist: 'Paper Satellites', dur: 204, art: 'linear-gradient(135deg, #ff5fa2, #7b61ff 55%, #1d1a5c)', bar: '#ff7ab8' },
  { title: 'Soft Focus', artist: 'Glasshouse Club', dur: 187, art: 'linear-gradient(160deg, #4fd1c5, #2b6cb0 60%, #1a2050)', bar: '#63e6d9' },
  { title: 'Low Orbit', artist: 'Marigold Static', dur: 231, art: 'radial-gradient(circle at 30% 30%, #ffd08a, #ff7a45 45%, #6b1f3a)', bar: '#ffb057' },
];
let ti = 0, elapsed = 48, ticker;
const fmt = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;

function showTrack(animateArt) {
  const t = tracks[ti];
  $$('[data-art]').forEach(el => el.style.setProperty('--art', t.art));
  notch.style.setProperty('--bar', t.bar);
  $('[data-title]').textContent = t.title;
  $('[data-artist]').textContent = t.artist;
  progress();
  if (animateArt && !reduced) {
    animate('.home-art, .live-art', { scale: [0.86, 1], opacity: [0.4, 1], duration: 600, ease: 'out(3)' });
  }
}
function progress() {
  const t = tracks[ti];
  notch.style.setProperty('--prog', (elapsed / t.dur).toFixed(4));
  $('[data-elapsed]').textContent = fmt(elapsed);
  $('[data-remaining]').textContent = '-' + fmt(t.dur - elapsed);
}
function setPlaying(on) {
  N.playing = on;
  body.classList.toggle('playing', on);
  $$('[data-playicon]').forEach(u => u.setAttribute('href', on ? '#i-pause' : '#i-play'));
  clearInterval(ticker);
  if (on) ticker = setInterval(() => {
    elapsed += 1;
    if (elapsed >= tracks[ti].dur) { ti = (ti + 1) % tracks.length; elapsed = 0; showTrack(true); }
    progress();
  }, 1000);
  render();
}
function skip(d) { ti = (ti + d + tracks.length) % tracks.length; elapsed = 0; showTrack(true); if (!N.playing) setPlaying(true); }

$$('[data-act]').forEach(b => b.addEventListener('click', () => {
  const act = b.dataset.act;
  if (act === 'play') setPlaying(!N.playing);
  if (act === 'next') skip(1);
  if (act === 'prev') skip(-1);
  if (!reduced) animate(b, { scale: [0.9, 1], duration: 500, ease: 'out(4)' });
}));

// ------------------------------------------------------------------ calendar + clocks

function calendar() {
  const now = new Date();
  $('[data-month]').textContent = now.toLocaleDateString(undefined, { month: 'short' });
  $('[data-year]').textContent = now.getFullYear();
  const days = $('[data-days]');
  days.innerHTML = '';
  for (let d = -2; d <= 2; d++) {
    const day = new Date(now); day.setDate(now.getDate() + d);
    const s = document.createElement('span');
    if (d === 0) s.className = 'today';
    s.innerHTML = `<small>${day.toLocaleDateString(undefined, { weekday: 'narrow' })}</small>${day.getDate()}`;
    days.append(s);
  }
  const at = mins => { const t = new Date(now.getTime() + mins * 60000); t.setSeconds(0); return t; };
  const time = t => t.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  const events = [
    { t: at(12), title: 'Design review', c: '#64d2ff' },
    { t: at(95), title: 'Lunch with Sam', c: '#ffd60a' },
    { t: at(270), title: 'Ship the release', c: '#bf5af2' },
  ];
  $('[data-events]').innerHTML = events.slice(0, 2).map(e => `<div class="ev" style="--c:${e.c}"><b>${e.title}</b><span>${time(e.t)}</span></div>`).join('');
  $('[data-nextup]').textContent = `${events[0].title} in 12 min`;
}
function clocks() {
  const now = new Date();
  $('[data-clock]').textContent = now.toLocaleString(undefined, { weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
  $('[data-bigtime]').textContent = now.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' }).replace(/\s?[AP]M/i, '');
}

// ------------------------------------------------------------------ bursts

// The same dozen dots the app fires when a file lands on the shelf.
function burst(x, y, radius = 52) {
  if (reduced) return;
  const dots = Array.from({ length: 12 }, (_, i) => {
    const d = document.createElement('span');
    Object.assign(d.style, {
      position: 'fixed', left: `${x - 3}px`, top: `${y - 3}px`, width: '6px', height: '6px', borderRadius: '50%',
      background: i % 3 === 0 ? '#b9a8ff' : '#fff', zIndex: 80, pointerEvents: 'none',
    });
    document.body.append(d);
    return d;
  });
  animate(dots, {
    x: (_, i) => Math.cos((i / 12) * Math.PI * 2) * radius,
    y: (_, i) => Math.sin((i / 12) * Math.PI * 2) * radius,
    opacity: [1, 0],
    duration: 700,
    ease: 'out(3)',
    onComplete: () => dots.forEach(d => d.remove()),
  });
}

// ------------------------------------------------------------------ shelf

function shelf() {
  const zone = $('[data-shelf]');
  const desk = $('[data-desk]');
  let interacted = false;

  function overNotch(x, y) {
    const r = notch.getBoundingClientRect();
    return x > r.left - 30 && x < r.right + 30 && y < r.bottom + 40;
  }
  function land(file) {
    const icon = $('.file-icon', file).cloneNode(true);
    const item = document.createElement('div');
    item.className = 'shelf-item';
    item.append(icon, document.createTextNode(file.dataset.file));
    zone.append(item);
    zone.classList.add('has-items');
    file.classList.add('gone');
    const r = item.getBoundingClientRect();
    burst(r.left + r.width / 2, r.top + 24);
    if (!reduced) animate(item, { scale: [0.6, 1], opacity: [0, 1], duration: 600, ease: 'out(4)' });
    if ($$('.file:not(.gone)', desk).length === 0) addReset();
  }
  function addReset() {
    if ($('.put-back', desk)) return;
    const b = document.createElement('button');
    b.className = 'copy put-back';
    b.textContent = 'Put the files back';
    Object.assign(b.style, { position: 'absolute', left: '50%', bottom: '22px', transform: 'translateX(-50%)' });
    b.onclick = () => {
      $$('.shelf-item', zone).forEach(i => i.remove());
      zone.classList.remove('has-items');
      $$('.file', desk).forEach(f => { f.classList.remove('gone'); f.style.transform = ''; });
      b.remove();
    };
    desk.append(b);
  }

  $$('.file', desk).forEach(file => {
    let sx, sy, dragging = false;
    file.addEventListener('pointerdown', e => {
      interacted = true;
      dragging = true;
      sx = e.clientX; sy = e.clientY;
      file.setPointerCapture(e.pointerId);
      file.classList.add('dragging');
    });
    file.addEventListener('pointermove', e => {
      if (!dragging) return;
      const dx = e.clientX - sx, dy = e.clientY - sy;
      file.style.transform = `translate(${dx}px, ${dy}px) scale(1.06)`;
      // Heading for the top of the screen opens the notch on the shelf, as a real
      // drag does.
      const near = e.clientY < 320;
      if (near !== (N.dragView === 'shelf')) { N.dragView = near ? 'shelf' : null; render(); }
      zone.classList.toggle('hot', overNotch(e.clientX, e.clientY));
    });
    const end = e => {
      if (!dragging) return;
      dragging = false;
      file.classList.remove('dragging');
      zone.classList.remove('hot');
      if (overNotch(e.clientX, e.clientY)) {
        land(file);
      } else if (!reduced) {
        const m = file.style.transform.match(/translate\(([-\d.]+)px, ([-\d.]+)px\)/);
        const [x, y] = m ? [+m[1], +m[2]] : [0, 0];
        file.style.transform = '';
        animate(file, { x: [x, 0], y: [y, 0], duration: 650, ease: 'out(4)' });
      } else {
        file.style.transform = '';
      }
      N.dragView = null;
      render();
    };
    file.addEventListener('pointerup', end);
    file.addEventListener('pointercancel', end);
  });

  // If someone reaches the chapter and just reads, show them once what a drag does.
  return function demoOnce() {
    if (interacted || reduced || $('.shelf-item', zone)) return;
    const file = $('.file', desk);
    const fr = file.getBoundingClientRect();
    const nr = notch.getBoundingClientRect();
    const tx = nr.left + nr.width * 0.3 - fr.left;
    const ty = nr.top + 70 - fr.top;
    interacted = true;
    file.classList.add('dragging');
    animate(file, {
      x: [0, tx * 0.35, tx], y: [0, ty * 0.55, ty], scale: [1, 1.08, 0.8],
      duration: 1500, ease: 'inOut(2)',
      onComplete: () => { file.classList.remove('dragging'); file.style.transform = ''; land(file); },
    });
  };
}

// ------------------------------------------------------------------ clipboard

function clipboard() {
  const list = $('[data-cliplist]');
  const colours = { Notes: '#ffd60a', Figma: '#a259ff', Terminal: '#8e8e93', Mail: '#0a84ff', Safari: '#30d158', Messages: '#34c759' };
  const seed = [
    ['Q4 plan: ship clipboard pins first', 'Notes'],
    ['#7B61FF', 'Figma'],
    ['brew install --cask lookatsarthak/tap/notchfun', 'Terminal'],
  ];
  const row = (text, app) => {
    const li = document.createElement('li');
    li.dataset.text = text.toLowerCase();
    li.innerHTML = `<span class="src" style="background:${colours[app] || '#888'}"></span><span class="t"></span><span class="a">${app}</span><kbd></kbd>`;
    $('.t', li).textContent = text;
    return li;
  };
  const number = () => $$('li:not(.none)', list).forEach((li, i) => ($('kbd', li).textContent = i < 9 ? `⌘${i + 1}` : ''));
  seed.slice(0, 3).forEach(([t, a]) => list.append(row(t, a)));
  number();

  $$('[data-copy]').forEach(b => b.addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(b.dataset.copy); } catch { /* the notch still shows it */ }
    const li = row(b.dataset.copy.replace(/^https:\/\//, ''), b.dataset.app);
    list.prepend(li);
    while ($$('li:not(.none)', list).length > 3) $$('li:not(.none)', list).pop().remove();
    number();
    if (!reduced) animate(li, { opacity: [0, 1], y: [-10, 0], duration: 500, ease: 'out(3)' });
    b.textContent = 'Copied';
    b.classList.add('done');
    setTimeout(() => { b.textContent = 'Copy'; b.classList.remove('done'); }, 1400);
  }));

  const q = $('[data-clipquery]');
  $('[data-clipsearch]').addEventListener('input', e => {
    const v = e.target.value.trim().toLowerCase();
    q.textContent = v || 'Type to search';
    q.parentElement.classList.toggle('typing', !!v);
    let shown = 0;
    $$('li:not(.none)', list).forEach(li => {
      const hit = !v || li.dataset.text.includes(v);
      li.classList.toggle('hide', !hit);
      shown += hit;
    });
    none.classList.toggle('hide', shown > 0);
  });
  const none = document.createElement('li');
  none.className = 'none hide';
  none.textContent = 'No matches';
  list.append(none);
}

// ------------------------------------------------------------------ keys

function keys() {
  const levels = { vol: 0.55, bright: 0.7 };
  const press = kind => {
    const [what, dir] = kind.split('-');
    levels[what] = Math.min(1, Math.max(0, levels[what] + (dir === 'up' ? 0.0625 : -0.0625)));
    const icon = what === 'vol' ? (levels.vol < 0.4 ? '#i-speaker-low' : '#i-speaker') : (levels.bright < 0.4 ? '#i-sun-low' : '#i-sun');
    $('.hud-icon use', notch).setAttribute('href', icon);
    notch.style.setProperty('--level', levels[what]);
    flash({ state: 'hud' }, 1500);
    const cap = $(`[data-key="${kind}"]`);
    cap?.classList.add('down');
    setTimeout(() => cap?.classList.remove('down'), 110);
  };
  $$('[data-key]').forEach(k => k.addEventListener('click', () => press(k.dataset.key)));
  addEventListener('keydown', e => {
    if (body.dataset.chapter !== 'keys') return;
    const map = { ArrowUp: 'vol-up', ArrowDown: 'vol-down', ArrowRight: 'bright-up', ArrowLeft: 'bright-down' };
    if (map[e.key]) { e.preventDefault(); press(map[e.key]); }
  });
}

// ------------------------------------------------------------------ little things

const little = {
  caffeine: {
    banner: { lead: '<svg viewBox="0 0 24 24" style="color:#ffd479"><use href="#i-cup"/></svg>Awake', trail: '<span data-count>59:59</span>' },
    caption: 'Awake for an hour, then back to normal. Or until you say so, or while an app is running.',
  },
  airpods: {
    banner: { lead: '<svg viewBox="0 0 24 24"><use href="#i-airpods"/></svg>AirPods Pro', trail: '82%<span class="ring" style="--p:.82"></span>' },
    caption: 'Connect them and the notch shows their battery for a moment. One honest number, not a left/right guess.',
  },
  charging: {
    banner: { lead: '<svg viewBox="0 0 24 24" style="color:#32d74b"><use href="#i-bolt"/></svg>Charging', trail: '84%<span class="ring" style="--p:.84"></span>' },
    caption: 'Plug in and it says so, with the level. Unplug, and it tells you that too.',
  },
  mirror: { view: 'mirror', caption: 'Open the mirror for a quick look before a call. It only uses the camera while it is open.' },
};
let littleTab = 'caffeine', countdown;
function applyLittle() {
  const t = little[littleTab];
  body.classList.toggle('awake', littleTab === 'caffeine');
  N.chapterBanner = t.banner || null;
  N.chapterView = t.view || null;
  bannerContent = null;
  render();
  $('[data-littlecaption]').textContent = t.caption;
  clearInterval(countdown);
  if (littleTab === 'caffeine') {
    let s = 3599;
    countdown = setInterval(() => { s -= 1; $$('[data-count]').forEach(el => (el.textContent = fmt(s))); }, 1000);
  }
}
$$('[data-little]').forEach(b => b.addEventListener('click', () => {
  littleTab = b.dataset.little;
  $$('[data-little]').forEach(x => x.setAttribute('aria-selected', String(x === b)));
  if (body.dataset.chapter === 'little') applyLittle();
  if (!reduced) animate('[data-littlecaption]', { opacity: [0, 1], y: [8, 0], duration: 450, ease: 'out(3)' });
}));

// ------------------------------------------------------------------ chapters

function chapters(shelfDemo) {
  const views = { music: 'home', shelf: 'shelf', clip: 'clip', cal: 'home' };
  let startedMusic = false, demoTimer;
  const enter = name => {
    body.dataset.chapter = name || '';
    N.chapterView = views[name] || null;
    N.chapterBanner = null;
    body.classList.remove('awake');
    clearInterval(countdown);
    clearTimeout(demoTimer);
    if (name === 'little') return applyLittle();
    if (name === 'music' && !startedMusic) { startedMusic = true; setPlaying(true); }
    if (name === 'shelf') demoTimer = setTimeout(shelfDemo, 3200);
    render();
  };
  // A chapter is current while it crosses the middle of the window.
  const current = new Set();
  const io = new IntersectionObserver(entries => {
    for (const e of entries) e.isIntersecting ? current.add(e.target.dataset.chapter) : current.delete(e.target.dataset.chapter);
    const name = [...current].pop();
    if ((name || '') !== (body.dataset.chapter || '')) enter(name);
  }, { rootMargin: '-50% 0px -50% 0px' });
  $$('[data-chapter]').forEach(s => io.observe(s));
}

// ------------------------------------------------------------------ bento

function bento() {
  $$('.card').forEach(c => c.addEventListener('pointermove', e => {
    const r = c.getBoundingClientRect();
    c.style.setProperty('--mx', `${e.clientX - r.left}px`);
    c.style.setProperty('--my', `${e.clientY - r.top}px`);
  }));
  const slider = $('[data-width]');
  const out = $('[data-widthout]');
  let t;
  slider.addEventListener('input', () => {
    document.documentElement.style.setProperty('--open-w', `${slider.value}px`);
    out.textContent = `${slider.value} pt`;
    fitNotch();
    N.preview = true; render();
    clearTimeout(t);
    t = setTimeout(() => { N.preview = false; render(); }, 1400);
  });
}

// ------------------------------------------------------------------ install

function install() {
  $$('[data-method]').forEach(b => b.addEventListener('click', () => {
    $$('[data-method]').forEach(x => x.setAttribute('aria-selected', String(x === b)));
    $$('[data-panel]').forEach(p => (p.hidden = p.dataset.panel !== b.dataset.method));
  }));
  $$('[data-copytext]').forEach(b => b.addEventListener('click', async () => {
    const text = b.previousElementSibling.textContent;
    try { await navigator.clipboard.writeText(text); b.textContent = 'Copied'; }
    catch { b.textContent = 'Select & copy'; }
    b.classList.add('done');
    setTimeout(() => { b.textContent = 'Copy'; b.classList.remove('done'); }, 1600);
  }));

  // The disk image window, installing itself on a loop while it's on screen.
  const dmg = $('[data-dmg]');
  if (reduced) return;
  const app = $('.dmg-app', dmg);
  const folder = $('.dmg-folder', dmg);
  const ghost = app.cloneNode();
  Object.assign(ghost.style, { position: 'absolute', opacity: 0, pointerEvents: 'none', zIndex: 2 });
  $('.dmg-body', dmg).append(ghost);
  let tl;
  const build = () => {
    const br = $('.dmg-body', dmg).getBoundingClientRect();
    const ar = app.getBoundingClientRect();
    const fr = folder.getBoundingClientRect();
    ghost.style.left = `${ar.left - br.left}px`;
    ghost.style.top = `${ar.top - br.top}px`;
    ghost.style.width = `${ar.width}px`;
    const dx = fr.left + fr.width / 2 - (ar.left + ar.width / 2);
    tl?.revert();
    tl = createTimeline({ loop: true, loopDelay: 1600, autoplay: false })
      .add(ghost, { opacity: [0, 0.9], scale: [1, 1.06], duration: 300, ease: 'out(2)' })
      .add(ghost, { x: [0, dx], y: [0, -26, 0], scale: [1.06, 0.62], duration: 1100, ease: 'inOut(2)' })
      .add(ghost, { opacity: 0, duration: 160 })
      .add(folder, { scale: [1, 1.12, 1], duration: 500, ease: 'out(3)' }, '-=120')
      .add('.dmg-hint', { opacity: [1, 0.3, 1], duration: 900 }, '-=500');
  };
  new IntersectionObserver(([e]) => {
    if (e.isIntersecting) { build(); tl.play(); } else tl?.pause();
  }, { threshold: 0.4 }).observe(dmg);
}

// ------------------------------------------------------------------ GitHub

async function gh(path) {
  const key = `gh:${path}`;
  try { const c = sessionStorage.getItem(key); if (c) return JSON.parse(c); } catch {}
  const res = await fetch(`https://api.github.com/repos/${REPO}${path}`, { headers: { Accept: 'application/vnd.github+json' } });
  if (!res.ok) throw new Error(res.status);
  const data = await res.json();
  try { sessionStorage.setItem(key, JSON.stringify(data)); } catch {}
  return data;
}

// Release notes follow a small house style (see release-notes/README.md): headings,
// bullets, bold leads. This renders just that much.
function md(src) {
  const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const inline = s => esc(s)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
    .replace(/\*([^*]+)\*/g, '<i>$1</i>')
    .replace(/\[([^\]]+)\]\((https?:[^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
  let html = '', inList = false, para = [];
  const flush = () => { if (para.length) { html += `<p>${inline(para.join(' '))}</p>`; para = []; } };
  for (const raw of src.replace(/\r/g, '').split('\n')) {
    const line = raw.trimEnd();
    const li = line.match(/^\s*[-*]\s+(.*)/);
    const h = line.match(/^#{1,4}\s+(.*)/);
    if (li) { flush(); if (!inList) { html += '<ul>'; inList = true; } html += `<li>${inline(li[1])}</li>`; continue; }
    if (/^\s{2,}\S/.test(line) && inList) { html = html.replace(/<\/li>$/, ` ${inline(line.trim())}</li>`); continue; }
    if (inList) { html += '</ul>'; inList = false; }
    if (h) { flush(); html += `<h4>${inline(h[1])}</h4>`; continue; }
    if (!line.trim()) { flush(); continue; }
    para.push(line.trim());
  }
  flush();
  if (inList) html += '</ul>';
  return html;
}

async function changelog() {
  const box = $('[data-releases]');
  try {
    const releases = (await gh('/releases?per_page=6')).filter(r => !r.draft && !r.prerelease).slice(0, 4);
    box.innerHTML = '';
    releases.forEach((r, i) => {
      const el = document.createElement('article');
      el.className = 'release reveal';
      const date = new Date(r.published_at).toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' });
      el.innerHTML = `
        <div class="release-head"><h3>${r.tag_name.replace(/^v/, '')}</h3><time>${date}</time>${i === 0 ? '<span class="latest">Latest</span>' : ''}</div>
        <div class="release-body">${md(r.body || 'No notes for this release.')}</div>`;
      box.append(el);
      const b = $('.release-body', el);
      if (b.scrollHeight > 300) {
        b.classList.add('clamped');
        const more = document.createElement('button');
        more.className = 'more';
        more.textContent = 'Show all';
        more.onclick = () => { b.classList.remove('clamped'); more.remove(); };
        el.append(more);
      }
    });
    const io = new IntersectionObserver(es => es.forEach(e => e.isIntersecting && (e.target.classList.add('in'), io.unobserve(e.target))), { rootMargin: '0px 0px -10% 0px' });
    $$('.release', box).forEach(r => io.observe(r));
    const latest = releases[0]?.tag_name.replace(/^v/, '');
    if (latest) $('[data-version]').textContent = `Version ${latest}`;
  } catch {
    box.innerHTML = '<p class="loading">Couldn\'t reach GitHub just now. <a href="https://github.com/lookatsarthak/NotchFun/releases">See the releases there →</a></p>';
  }
}

async function starCount() {
  try {
    const repo = await gh('');
    const n = repo.stargazers_count;
    if (n < 10) return;
    const label = n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(n);
    $('[data-stars]').textContent = `${label} stars`;
    $('[data-stars2]').textContent = `Star — ${label} so far`;
  } catch {}
}

// The timeline line draws itself as you read down the releases.
function timelineLine() {
  const tl = $('.timeline');
  const path = $('.timeline-line path');
  path.style.strokeDasharray = '100 100';
  path.setAttribute('pathLength', '100');
  const update = () => {
    const r = tl.getBoundingClientRect();
    const p = Math.min(1, Math.max(0, (innerHeight * 0.7 - r.top) / r.height));
    path.style.strokeDashoffset = String(100 - p * 100);
  };
  addEventListener('scroll', () => requestAnimationFrame(update), { passive: true });
  update();
}

// ------------------------------------------------------------------ real footage

// The recordings play only while on screen, and not at all on their own for people
// who asked for less motion — they get the poster and a play control instead.
function footage() {
  const videos = $$('.clip video');
  if (reduced) { videos.forEach(v => (v.controls = true)); return; }
  const io = new IntersectionObserver(entries => {
    for (const e of entries) {
      const v = e.target;
      if (e.isIntersecting) { v.preload = 'auto'; v.play().catch(() => {}); } else v.pause();
    }
  }, { threshold: 0.35 });
  videos.forEach(v => io.observe(v));
}

// ------------------------------------------------------------------ go

showTrack(false);
calendar();
clocks();
setInterval(clocks, 10_000);
setupReveals();
starfield();
const shelfDemo = shelf();
clipboard();
keys();
chapters(shelfDemo);
bento();
install();
changelog();
starCount();
timelineLine();
footage();
render();
introHero();
playHello();
