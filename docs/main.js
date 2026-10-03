// NotchFun — site behaviour.
//
// One idea runs through the page: the black shape pinned to the top of the window is
// the product. Each chapter drives it the way the real app would, so reading the page
// is watching the notch work. anime.js does the choreography (the hello, bursts, the
// disk-image drag); CSS springs, sampled from the app's own, move the notch itself.

import { animate, createTimeline, createDrawable, stagger } from 'https://cdn.jsdelivr.net/npm/animejs@4.5.0/dist/bundles/anime.esm.min.js';
import { API, track, downloadURL, platform } from './api.js';
import { feedbackDialog } from './feedback.js';
import { insights } from './insights.js';

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
  tour: null,           // the hero's run-through: { state, view, banner }
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
  else if (N.tour) { state = N.tour.state; view = N.tour.view || view; if (N.tour.banner) setBanner(N.tour.banner); }
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
    l.style.cssText = notch.style.cssText.replace(/--(ns|ts):[^;]+;?/g, '') + `--ls:${scale};`;
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
  if (reduced) return Promise.resolve();
  N.hello = true;
  render();
  const [drawable] = createDrawable('.hello-path');
  drawable.setAttribute('draw', '0 0');
  return new Promise(resolve => {
    animate(drawable, {
      draw: ['0 0', '0 1'],
      duration: 2600,
      delay: 450,
      ease: 'inOut(1.6)',
      onComplete: () => setTimeout(() => { N.hello = false; render(); resolve(); }, 300),
    });
  });
}

// ------------------------------------------------------------------ hero

// Up top the notch is drawn large and runs through its day, with the line above the
// headline naming each thing as it happens. Scrolling shrinks it into the menu bar.
const heroEl = $('[data-hero]');
let heroScale = 1;

function dock() {
  const root = document.documentElement;
  const ns = parseFloat(root.style.getPropertyValue('--ns')) || 1;
  const openW = parseFloat(getComputedStyle(root).getPropertyValue('--open-w')) || 640;
  // Height counts too, so on a 13" MacBook the headline and buttons still fit above the fold.
  heroScale = Math.max(ns, Math.min(1.6, (root.clientWidth - 64) / openW, (innerHeight * 0.3) / 190));
  root.style.setProperty('--hero-s', heroScale.toFixed(3));
  const p = Math.min(1, Math.max(0, scrollY / (innerHeight * 0.55)));
  const eased = 1 - Math.pow(1 - p, 3);
  root.style.setProperty('--ts', (heroScale + (ns - heroScale) * eased).toFixed(4));
  // The menu bar's links sit behind the large notch, so they arrive as it docks.
  root.style.setProperty('--dock', eased.toFixed(3));
}

function numberClips() {
  $$('[data-cliplist] li:not(.none)').forEach((li, i) => ($('kbd', li).textContent = i < 9 ? `⌘${i + 1}` : ''));
}
addEventListener('scroll', () => requestAnimationFrame(dock), { passive: true });
addEventListener('resize', dock);

// Swaps the kicker's words: the old line rolls up and out, the new one rolls in, and
// the box eases to the new width so the sentence never jumps.
let kickerText = '';
function kick(text) {
  if (text === kickerText) return;
  kickerText = text;
  const roll = $('[data-kicker]');
  const next = document.createElement('span');
  next.textContent = text;
  const prev = roll.firstElementChild;
  if (reduced || !prev) { roll.replaceChildren(next); return; }
  next.style.position = 'absolute'; next.style.left = '0'; next.style.top = '0';
  roll.append(next);
  const w = next.getBoundingClientRect().width;
  animate(roll, { width: [roll.getBoundingClientRect().width, w], duration: 500, ease: 'out(3)' });
  animate(prev, { y: ['0%', '-110%'], opacity: [1, 0], duration: 420, ease: 'in(2)', onComplete: () => prev.remove() });
  animate(next, { y: ['110%', '0%'], opacity: [0, 1], duration: 520, delay: 120, ease: 'out(3)',
    onComplete: () => { next.style.position = ''; roll.style.width = ''; } });
}

function tour() {
  if (reduced) { N.tour = { state: 'open', view: 'home' }; render(); return; }
  const zone = $('[data-shelf]');
  const list = $('[data-cliplist]');
  let extra = null;
  const cleanup = () => { const wasRow = extra?.tagName === 'LI'; extra?.remove(); extra = null; if (wasRow) numberClips(); zone.classList.toggle('has-items', !!$('.shelf-item', zone)); body.removeAttribute('data-focus'); };
  const steps = [
    { kicker: 'plays your music.', ms: 2400, run: () => { setPlaying(true); N.tour = { state: 'live' }; } },
    { kicker: 'plays your music.', ms: 3000, run: () => { N.tour = { state: 'open', view: 'home' }; } },
    { kicker: 'holds your files.', ms: 3200, run: () => {
      N.tour = { state: 'open', view: 'shelf' };
      setTimeout(() => {
        extra = document.createElement('div');
        extra.className = 'shelf-item';
        extra.innerHTML = '<span class="file-icon pdf">PDF</span>Boarding pass.pdf';
        zone.append(extra); zone.classList.add('has-items');
        animate(extra, { scale: [0.5, 1], opacity: [0, 1], y: [-30, 0], duration: 700, ease: 'out(4)' });
        const r = extra.getBoundingClientRect(); burst(r.left + r.width / 2, r.top + 20 * heroScale, 40 * heroScale);
      }, 650);
    } },
    { kicker: 'remembers what you copied.', ms: 3200, run: () => {
      N.tour = { state: 'open', view: 'clip' };
      setTimeout(() => {
        extra = document.createElement('li');
        extra.innerHTML = '<span class="src" style="background:#ffd60a"></span><span class="t">Flight AA 2417 · Gate B32</span><span class="a">Notes</span><kbd>⌘1</kbd>';
        list.prepend(extra);
        numberClips();
        animate(extra, { opacity: [0, 1], y: [-12, 0], duration: 600, ease: 'out(3)' });
      }, 600);
    } },
    { kicker: 'shows what’s next.', ms: 2800, run: () => { body.dataset.focus = 'cal'; N.tour = { state: 'open', view: 'home' }; } },
    { kicker: 'keeps your Mac awake.', ms: 2600, run: () => {
      N.tour = { state: 'banner', banner: { lead: '<svg viewBox="0 0 24 24" style="color:#ffd479"><use href="#i-cup"/></svg>Awake', trail: '<span>1:00:00</span>' } };
      bannerContent = null;
    } },
    { kicker: 'turns it down, quietly.', ms: 2400, run: () => {
      N.tour = { state: 'hud' };
      $('.hud-icon use', notch).setAttribute('href', '#i-speaker');
      [0.3, 0.42, 0.55, 0.68].forEach((l, i) => setTimeout(() => { notch.style.setProperty('--level', l); syncLoupes(notch.dataset.state); }, 300 + i * 260));
    } },
  ];
  let i = 0, timer = null, running = false;
  const step = () => {
    cleanup();
    const st = steps[i];
    kick(st.kicker);
    st.run();
    render();
    i = (i + 1) % steps.length;
    timer = setTimeout(step, st.ms);
  };
  const start = () => { if (running) return; running = true; step(); };
  const stop = () => { if (!running) return; running = false; clearTimeout(timer); cleanup(); N.tour = null; render(); };
  // Runs only while the hero is on screen; reaching for the notch takes over from it.
  new IntersectionObserver(([e]) => (e.intersectionRatio > 0.35 ? start() : stop()), { threshold: [0, 0.35, 0.6] }).observe(heroEl);
  notch.addEventListener('pointerenter', () => { if (running) { clearTimeout(timer); } });
  notch.addEventListener('pointerleave', () => { if (running) { clearTimeout(timer); timer = setTimeout(step, 1200); } });
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
  // The hero is what's on screen at load; it fades in straight away rather than waiting
  // to be scrolled into view (on a short window the buttons sit in the bottom strip).
  $$('[data-hero] .reveal').forEach(el => requestAnimationFrame(() => el.classList.add('in')));
  $$('.reveal, .reveal-lines').forEach(el => el.closest('[data-hero]') && el.classList.contains('reveal') ? null : io.observe(el));
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
  if (N.playing === on) return;
  N.playing = on;
  body.classList.toggle('playing', on);
  // Everything else follows in CSS from body.playing: the glyphs swap like an SF Symbol
  // replace, the artwork eases forward, the waveform wakes up.
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
    file.classList.remove('lifted');
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
      $$('.file', desk).forEach(f => f.classList.remove('gone', 'lifted'));
      b.remove();
    };
    desk.append(b);
  }

  // A dragged file leaves the desk: a copy of it is lifted into a fixed layer above
  // the whole page, so it stays in sight all the way up to the notch.
  function lift(file) {
    const r = file.getBoundingClientRect();
    const ghost = document.createElement('div');
    ghost.className = 'file-ghost';
    ghost.innerHTML = file.innerHTML;
    Object.assign(ghost.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px` });
    document.body.append(ghost);
    file.classList.add('lifted');
    return { ghost, r };
  }
  function drop(file, ghost, into) {
    if (into) {
      animate(ghost, { scale: 0.4, opacity: 0, duration: 260, ease: 'in(2)', onComplete: () => { ghost.remove(); land(file); } });
      return;
    }
    // Missed: it springs home, like a drag macOS refuses.
    animate(ghost, { x: 0, y: 0, rotate: 0, scale: 1, duration: reduced ? 0 : 650, ease: 'out(4)',
      onComplete: () => { ghost.remove(); file.classList.remove('lifted'); } });
  }

  $$('.file', desk).forEach(file => {
    let sx, sy, lastX, ghost = null;
    file.addEventListener('pointerdown', e => {
      interacted = true;
      sx = lastX = e.clientX; sy = e.clientY;
      file.setPointerCapture(e.pointerId);
      ({ ghost } = lift(file));
      animate(ghost, { scale: 1.08, duration: 200, ease: 'out(3)' });
    });
    file.addEventListener('pointermove', e => {
      if (!ghost) return;
      const dx = e.clientX - sx, dy = e.clientY - sy;
      // A little tilt in the direction of travel, as if it has some weight.
      const tilt = Math.max(-10, Math.min(10, (e.clientX - lastX) * 0.8));
      lastX = e.clientX;
      ghost.style.transform = `translate(${dx}px, ${dy}px) scale(1.08) rotate(${tilt}deg)`;
      // Heading for the top of the screen opens the notch on the shelf, as a real drag does.
      const near = e.clientY < 320;
      if (near !== (N.dragView === 'shelf')) { N.dragView = near ? 'shelf' : null; render(); }
      zone.classList.toggle('hot', overNotch(e.clientX, e.clientY));
    });
    const end = e => {
      if (!ghost) return;
      const g = ghost; ghost = null;
      zone.classList.remove('hot');
      const m = g.style.transform.match(/translate\(([-\d.]+)px, ([-\d.]+)px\)/);
      if (m) { g.style.transform = ''; animate(g, { x: +m[1], y: +m[2], scale: 1.08, duration: 0 }); }
      drop(file, g, overNotch(e.clientX, e.clientY));
      N.dragView = null;
      render();
    };
    file.addEventListener('pointerup', end);
    file.addEventListener('pointercancel', end);
  });

  // If someone reaches the chapter and just reads, show them once what a drag does.
  return function demoOnce() {
    if (interacted || reduced || $('.shelf-item', zone)) return;
    interacted = true;
    const file = $('.file', desk);
    const { ghost, r } = lift(file);
    N.dragView = 'shelf'; render();
    setTimeout(() => {
      const nr = notch.getBoundingClientRect();
      const tx = nr.left + nr.width * 0.3 - r.left;
      const ty = nr.top + 70 - r.top;
      animate(ghost, {
        x: [0, tx * 0.3, tx], y: [0, ty * 0.6, ty], rotate: [0, -6, 0], scale: [1, 1.1, 1],
        duration: 1400, ease: 'inOut(2)',
        onComplete: () => { drop(file, ghost, true); N.dragView = null; render(); },
      });
    }, 350);
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
  const number = numberClips;
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
    caption: 'Stay awake for the download. Sleep when it’s done.',
  },
  airpods: {
    banner: { lead: '<svg viewBox="0 0 24 24"><use href="#i-airpods"/></svg>AirPods Pro', trail: '82%<span class="ring" style="--p:.82"></span>' },
    caption: 'Pop them in, see the battery. One honest number.',
  },
  charging: {
    banner: { lead: '<svg viewBox="0 0 24 24" style="color:#32d74b"><use href="#i-bolt"/></svg>Charging', trail: '84%<span class="ring" style="--p:.84"></span>' },
    caption: 'Plug in, it tells you. Unplug, same.',
  },
  mirror: { view: 'mirror', caption: 'A quick look before the call. Nothing’s recorded.' },
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
  let t;
  slider.addEventListener('input', () => {
    document.documentElement.style.setProperty('--open-w', `${slider.value}px`);
    slider.closest('.card').style.setProperty('--demo-w', slider.value);
    fitNotch(); dock();
    N.preview = true; render();
    clearTimeout(t);
    t = setTimeout(() => { N.preview = false; render(); }, 1400);
  });
}

// ------------------------------------------------------------------ install

function install() {
  $$('[data-copytext]').forEach(b => b.addEventListener('click', async () => {
    const text = b.previousElementSibling.textContent;
    try { await navigator.clipboard.writeText(text); b.textContent = 'Copied'; }
    catch { b.textContent = 'Select & copy'; }
    b.classList.add('done');
    const r = b.getBoundingClientRect(); burst(r.left + r.width / 2, r.top + r.height / 2, 30);
    setTimeout(() => { b.textContent = 'Copy'; b.classList.remove('done'); }, 1600);
    // A web page can't open Terminal with the line typed in (browsers block that, rightly),
    // so the next best thing: say exactly what to press next, right under the button.
    if ('next' in b.dataset) {
      const next = $('[data-copiednext]');
      next.hidden = false;
      if (!reduced) animate(next, { opacity: [0, 1], y: [-6, 0], duration: 450, ease: 'out(3)' });
    }
  }));

  // Homebrew copies its command, and says so.
  const brew = $('[data-brew]');
  brew.addEventListener('click', async () => {
    const label = $('[data-brewlabel]');
    try { await navigator.clipboard.writeText(brew.dataset.brew); label.textContent = 'Copied — paste it in Terminal'; }
    catch { label.textContent = brew.dataset.brew; }
    brew.classList.add('done');
    setTimeout(() => { label.textContent = 'Copy the brew command'; brew.classList.remove('done'); }, 2600);
  });

  // The three steps play in turn: the copy button gets clicked, Spotlight finds
  // Terminal, Return is pressed and NotchFun is ready. On a loop while on screen.
  const box = $('[data-steps]');
  const steps = $$('.step', box);
  const typed = $('[data-s2]', box);
  if (reduced) { steps.forEach(s => s.classList.add('active')); steps[1].classList.add('found'); typed.textContent = 'Terminal'; steps[2].classList.add('done'); return; }
  let run = 0;
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  async function play() {
    const id = ++run;
    const live = () => id === run;
    steps.forEach(s => s.classList.remove('active', 'clicked', 'found', 'pressed', 'done'));
    typed.textContent = '';
    steps[0].classList.add('active'); await sleep(900); if (!live()) return;
    steps[0].classList.add('clicked'); await sleep(1300); if (!live()) return;
    steps[0].classList.remove('active'); steps[1].classList.add('active');
    for (const ch of 'Terminal') { await sleep(110); if (!live()) return; typed.textContent += ch; }
    steps[1].classList.add('found'); await sleep(1400); if (!live()) return;
    steps[1].classList.remove('active'); steps[2].classList.add('active'); await sleep(700); if (!live()) return;
    steps[2].classList.add('pressed'); await sleep(160); steps[2].classList.remove('pressed'); await sleep(350); if (!live()) return;
    steps[2].classList.add('done'); await sleep(2800); if (!live()) return;
    play();
  }
  new IntersectionObserver(([e]) => (e.isIntersecting ? play() : run++), { threshold: 0.35 }).observe(box);
}

// ------------------------------------------------------------------ buttons

// The hero buttons lean toward the pointer, and the download one says what it's doing.
function buttons() {
  if (!reduced) $$('.magnetic').forEach(b => {
    b.addEventListener('pointermove', e => {
      const r = b.getBoundingClientRect();
      const x = (e.clientX - r.left - r.width / 2) * 0.22;
      const y = (e.clientY - r.top - r.height / 2) * 0.35;
      animate(b, { x, y, duration: 350, ease: 'out(3)' });
    });
    b.addEventListener('pointerleave', () => animate(b, { x: 0, y: 0, duration: 700, ease: 'out(4)' }));
  });
  const dl = $('[data-download]');
  const label = (text) => {
    const roll = $('.roll', dl);
    roll.dataset.label = text;
    $('span', roll).textContent = text;
  };
  // Only Macs can run NotchFun. Everyone else gets "Send to my Mac" instead of a download
  // they can't use: the share sheet (AirDrop, Messages, Mail) or an email to themselves.
  if (!platform.startsWith('mac/')) {
    sendToMac(dl, label);
    return void $('[data-star]').addEventListener('click', () => {
      const r = $('[data-star]').getBoundingClientRect(); burst(r.left + 34, r.top + r.height / 2, 40);
    });
  }
  dl.addEventListener('click', () => {
    const r = dl.getBoundingClientRect(); burst(r.left + 32, r.top + r.height / 2, 44);
    dl.classList.add('downloading');
    label('Downloading…');
    setTimeout(() => { dl.classList.remove('downloading'); label('Check your Downloads'); }, 2200);
    setTimeout(() => label('Download for Mac'), 6500);
  });
  $('[data-star]').addEventListener('click', () => {
    const r = $('[data-star]').getBoundingClientRect(); burst(r.left + 34, r.top + r.height / 2, 40);
  });
}

// ------------------------------------------------------------------ send to my Mac

const SEND_URL = 'https://lookatsarthak.github.io/NotchFun/?ref=sent';
const SEND_TEXT = 'NotchFun turns the MacBook notch into a home for music, files and your clipboard. Open this on your Mac to install it.';

function sendToMac(button, label) {
  button.removeAttribute('data-dl');
  button.href = '#send';
  button.classList.add('send-mac');
  $('.btn-icon', button).outerHTML = '<span class="btn-icon send-icon" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M21 3 10.5 13.5M21 3l-6.5 18-4-7.5L3 9.5z"/></svg></span>';
  label('Send to my Mac');

  const sheet = document.createElement('dialog');
  sheet.className = 'fb-dialog send-sheet';
  sheet.setAttribute('aria-labelledby', 'send-title');
  sheet.innerHTML = `
    <div class="fb-head"><h2 id="send-title">Send it to your Mac</h2><button class="fb-close" type="button" aria-label="Close">×</button></div>
    <div class="fb-body">
      <p class="send-lede">NotchFun runs on Macs with macOS 26 or later. Send yourself the link and open it there.</p>
      <div class="send-actions">
        <label class="fb-field send-field"><span class="fb-label">Your email <small>so it's filled in for you</small></span>
          <input type="email" name="send-to" autofocus autocomplete="email" inputmode="email" autocapitalize="off" spellcheck="false" placeholder="you@example.com"></label>
        <a class="send-btn" data-send="email" href="#">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3.5 6.5h17v11h-17zM3.5 7l8.5 6.5L20.5 7"/></svg><span>Email it to myself</span></a>
        <button class="send-btn" data-send="copy" type="button">
          <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="8.5" y="8.5" width="11" height="11" rx="2.5"/><path d="M15.5 5.5v-1a2 2 0 0 0-2-2h-8a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h1"/></svg><span>Copy link</span></button>
      </div>
    </div>`;
  document.body.append(sheet);
  $('.fb-close', sheet).addEventListener('click', () => sheet.close());
  sheet.addEventListener('click', e => { if (e.target === sheet) sheet.close(); });
  // Their own mail app opens with To, subject and the link filled in; they tap Send. Nothing
  // is sent or kept by the site, so the address never leaves their device.
  const to = $('[name="send-to"]', sheet);
  const mailto = () => {
    const address = /^[^\s@,;?&]+@[^\s@,;?&]+\.[^\s@,;?&]+$/.test(to.value.trim()) ? to.value.trim() : '';
    return `mailto:${address}?subject=${encodeURIComponent('NotchFun for my Mac')}&body=${encodeURIComponent(`${SEND_TEXT}\n\n${SEND_URL}`)}`;
  };
  const email = $('[data-send="email"]', sheet);
  to.addEventListener('input', () => (email.href = mailto()));
  to.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); email.click(); } });
  email.href = mailto();
  email.addEventListener('click', () => { email.href = mailto(); track('send_mac', 'email'); });
  $('[data-send="copy"]', sheet).addEventListener('click', async e => {
    const b = e.currentTarget;
    try { await navigator.clipboard.writeText(SEND_URL); $('span', b).textContent = 'Copied. Paste it anywhere you’ll see on your Mac'; }
    catch { $('span', b).textContent = SEND_URL; }
    track('send_mac', 'copy');
  });

  button.addEventListener('click', async e => {
    e.preventDefault();
    const r = button.getBoundingClientRect(); burst(r.left + 32, r.top + r.height / 2, 30);
    track('send_mac', 'open');
    const data = { title: 'NotchFun', text: SEND_TEXT, url: SEND_URL };
    if (navigator.share && (!navigator.canShare || navigator.canShare(data))) {
      try {
        await navigator.share(data);
        track('send_mac', 'share');
        label('Sent. Open it on your Mac');
        setTimeout(() => label('Send to my Mac'), 5000);
        return;
      } catch (err) {
        if (err?.name === 'AbortError') return; // they closed the share sheet
      }
    }
    sheet.showModal();
  });
}

// ------------------------------------------------------------------ counts

// Anonymous counts for the maintainer (see api.js for exactly what, and how to opt out).
function counts() {
  $$('[data-dl]').forEach(a => (a.href = downloadURL(a.dataset.dl)));

  const params = new URLSearchParams(location.search);
  let from = params.get('utm_source') || params.get('ref') || '';
  if (!from && document.referrer) {
    try { const host = new URL(document.referrer).hostname; if (host !== location.hostname) from = host; } catch {}
  }
  insights(from.toLowerCase().slice(0, 64));

  const installSeen = new IntersectionObserver(([e]) => {
    if (e.isIntersecting) { track('install_seen'); installSeen.disconnect(); }
  }, { threshold: 0.4 });
  installSeen.observe($('#install'));

  $$('[data-copytext]').forEach(b => b.addEventListener('click', () => track('copy_curl', 'install')));
  $('[data-brew]').addEventListener('click', () => track('copy_brew', 'install'));
  $$('[data-starfrom]').forEach(a => a.addEventListener('click', () => track('star_click', a.dataset.starfrom)));
}

// ------------------------------------------------------------------ GitHub

// Through the backend, which asks GitHub once every 10 minutes for everyone; straight
// from GitHub only if the backend can't be reached.
async function gh(path) {
  const key = `gh:${path}`;
  try { const c = sessionStorage.getItem(key); if (c) return JSON.parse(c); } catch {}
  let res = await fetch(`${API}/gh/${path ? 'releases' : 'repo'}`).catch(() => null);
  if (!res?.ok) res = await fetch(`https://api.github.com/repos/${REPO}${path}`, { headers: { Accept: 'application/vnd.github+json' } });
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
    // The download button shows the real size of the disk image.
    const dmg = releases[0]?.assets?.find(a => a.name === 'NotchFun.dmg');
    if (dmg) $('[data-dmgsize]').textContent = `Disk image · ${(dmg.size / 1e6).toFixed(1)} MB`;
    // The update card shows the real last step: previous release to the current one.
    const v = r => r?.tag_name.replace(/^v/, '');
    if (releases[1]) { $('.ud-old').textContent = v(releases[1]); $('.ud-new').textContent = v(releases[0]); }
  } catch {
    box.innerHTML = '<p class="loading">Couldn\'t reach GitHub just now. <a href="https://github.com/lookatsarthak/NotchFun/releases">See the releases there →</a></p>';
  }
}

// The total downloads of every release file, counted up from zero the first time it's on
// screen. Left out entirely if the backend can't be reached.
async function downloadCount() {
  const wrap = $('[data-downloads]');
  let total;
  try {
    const res = await fetch(`${API}/gh/downloads`);
    if (!res.ok) return;
    ({ downloads: total } = await res.json());
  } catch { return; }
  if (!Number.isFinite(total) || total <= 0) return;
  const out = $('[data-downloads-n]');
  const show = n => (out.textContent = Math.round(n).toLocaleString());
  wrap.hidden = false;
  if (reduced) return show(total);
  show(0);
  const io = new IntersectionObserver(([e]) => {
    if (!e.isIntersecting) return;
    io.disconnect();
    const counter = { n: 0 };
    animate(counter, { n: total, duration: 1400, ease: 'out(4)', onUpdate: () => show(counter.n) });
  });
  io.observe(wrap);
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

// "Try it" or "Watch the real app": the recording replaces the demo in place, and only
// plays while it is showing.
function propSwitches() {
  $$('[data-prop]').forEach(prop => {
    const video = $('video', prop);
    $$('[data-show]', prop).forEach(b => b.addEventListener('click', () => {
      const show = b.dataset.show;
      $$('[data-show]', prop).forEach(x => x.setAttribute('aria-selected', String(x === b)));
      $$('[data-face]', prop).forEach(f => {
        const on = f.dataset.face === show;
        f.hidden = !on;
        if (on && !reduced) animate(f, { opacity: [0, 1], scale: [0.97, 1], duration: 450, ease: 'out(3)' });
        if (on) f.classList.add('in');
      });
      if (show === 'real') { video.preload = 'auto'; if (reduced) video.controls = true; else video.play().catch(() => {}); }
      else video.pause();
    }));
  });
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
downloadCount();
timelineLine();
propSwitches();
buttons();
counts();
feedbackDialog();
dock();
render();
introHero();
playHello().then(tour);
