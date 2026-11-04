// NotchFun — site behaviour.
//
// One idea runs through the page: the black shape pinned to the top of the window is
// the product. Each chapter drives it the way the real app would, so reading the page
// is watching the notch work. anime.js does the choreography (the hello, bursts, the
// disk-image drag); CSS springs, sampled from the app's own, move the notch itself.

import { animate, createDrawable } from './vendor/anime-4.5.0.esm.min.js';
import { API, track, downloadURL } from './api.js';
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
  peek: null,           // briefly open on one view, over everything but the greeting
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
  else if (N.peek) { state = 'open'; view = N.peek; }
  else if (N.dragView) { state = 'open'; view = N.dragView; }
  else if (N.chapterView) { state = 'open'; view = N.chapterView; }
  else if (N.chapterBanner) { state = 'banner'; setBanner(N.chapterBanner); }
  else if (N.preview) { state = 'open'; view = 'home'; }
  else if (N.hover) { state = 'open'; view = view === 'mirror' ? 'home' : view; }
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
  // The mirror has nothing to show up close, so the magnified notch doesn't play music at it.
  const resting = N.playing && N.chapterView !== 'mirror' ? 'live' : 'closed';
  const closed = ['closed', 'live', 'hud', 'banner'].includes(state) ? state : resting;
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

let peekTimer;
function peek(view, ms = 3000) {
  N.peek = view;
  render();
  clearTimeout(peekTimer);
  peekTimer = setTimeout(() => { N.peek = null; render(); }, ms);
}

// Hovering the page's notch opens it, like the app's "open on hover".
let hoverTimer;
notch.addEventListener('pointerenter', () => { clearTimeout(hoverTimer); N.hover = true; render(); });
notch.addEventListener('pointerleave', () => { hoverTimer = setTimeout(() => { N.hover = false; render(); }, 180); });

// On narrow screens the open notch is scaled to fit rather than clipped.
// The sizes themselves come from nfNotchSize() in index.html's <head>, which also applies
// them before the first paint.
function fitNotch() {
  document.documentElement.style.setProperty('--ns', nfNotchSize().ns.toFixed(3));
}
addEventListener('resize', fitNotch);
fitNotch();

// ------------------------------------------------------------------ hello

// The first thing the app does on a new Mac: open the notch and write "hello" in it.
// The page does the same, with the app's own path.
let drawable;
function playHello() {
  if (reduced) return Promise.resolve();
  N.hello = true;
  render();
  drawable ??= createDrawable('.hello-path')[0];
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

// The page ends where it began. Reaching the closing section writes hello once more,
// which is the moment it's asking the visitor to go and get on their own Mac.
function closingHello() {
  const io = new IntersectionObserver(([e]) => {
    if (!e.isIntersecting) return;
    io.disconnect();
    if (!N.hello) playHello();
  }, { threshold: 0.6 });
  io.observe($('[data-closing]'));
}

// ------------------------------------------------------------------ hero

// Up top the notch is drawn large and runs through its day, with the line above the
// headline naming each thing as it happens. Scrolling shrinks it into the menu bar.
const heroEl = $('[data-hero]');
let heroScale = 1;

function dock() {
  const root = document.documentElement;
  const { ns, hero } = nfNotchSize();
  heroScale = hero;
  root.style.setProperty('--hero-s', heroScale.toFixed(3));
  const p = Math.min(1, Math.max(0, scrollY / (innerHeight * 0.55)));
  const eased = 1 - Math.pow(1 - p, 3);
  root.style.setProperty('--ts', (heroScale + (ns - heroScale) * eased).toFixed(4));
  // The menu bar's links sit behind the large notch, so they arrive as it docks.
  root.style.setProperty('--dock', eased.toFixed(3));
  // Fully faded means fully gone: nothing to tab to behind the large notch.
  root.toggleAttribute('data-undocked', eased < 0.02);
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
  if (reduced) {
    // No run-through: the notch simply sits open on the home view while the hero is on
    // screen, and closes when it isn't.
    new IntersectionObserver(([e]) => {
      N.tour = e.intersectionRatio > 0.35 ? { state: 'open', view: 'home' } : null;
      render();
    }, { threshold: [0, 0.35, 0.6] }).observe(heroEl);
    return;
  }
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
  $$('[data-hero] .reveal').forEach(el => el.classList.add('in')); // already animating in via CSS
  $$('.reveal, .reveal-lines').forEach(el => el.closest('[data-hero]') && el.classList.contains('reveal') ? null : io.observe(el));
}

// The headline's rise is CSS now (styles.css, line-up), so it doesn't wait for this script.
function introHero() {
  if (reduced) $$('.headline .line > span').forEach(l => (l.style.transform = 'none'));
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
  $('[data-playfoot]').textContent = on ? 'Keep scrolling. The music comes with you.' : 'Hit play, then keep scrolling.';
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

// A made-up week around today, at ordinary times, so it reads the same at any hour. Picking
// a day in the card moves the selection in the notch's own calendar, as tapping one does
// in the app.
const week = {
  '-2': [['Stand-up', 9, 30, '#64d2ff'], ['Dentist', 16, 0, '#ffd60a']],
  '-1': [['Sprint review', 11, 0, '#bf5af2']],
  '0': [['Design review', 10, 30, '#64d2ff'], ['Lunch with Sam', 13, 0, '#ffd60a'], ['Ship the release', 16, 30, '#bf5af2']],
  '1': [['Stand-up', 9, 30, '#64d2ff'], ['Call with the bank', 14, 15, '#30d158']],
  '2': [],
};

function calendar() {
  const now = new Date();
  const dayAt = d => { const day = new Date(now); day.setDate(now.getDate() + d); return day; };
  const time = (d, h, m) => { const t = dayAt(d); t.setHours(h, m, 0, 0); return t.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' }); };
  const offsets = [-2, -1, 0, 1, 2];
  const days = $('[data-days]');
  const pick = $('[data-calpick]');
  const agenda = $('[data-agenda]');
  const events = $('[data-events]');

  const show = d => {
    const list = week[d];
    const date = dayAt(d);
    $('[data-month]').textContent = date.toLocaleDateString(undefined, { month: 'short' });
    $('[data-year]').textContent = date.getFullYear();
    offsets.forEach((o, i) => {
      days.children[i].classList.toggle('today', o === d);
      pick.children[i].setAttribute('aria-pressed', String(o === d));
    });
    const row = ([title, h, m, c]) => ({ title, c, at: time(d, h, m) });
    events.innerHTML = list.length
      ? list.slice(0, 2).map(row).map(e => `<div class="ev" style="--c:${e.c}"><b>${e.title}</b><span>${e.at}</span></div>`).join('')
      : '<div class="ev-none">Nothing planned</div>';
    agenda.innerHTML = list.length
      ? list.map(row).map(e => `<li style="--c:${e.c}"><b>${e.title}</b><span>${e.at}</span></li>`).join('')
      : '<li class="agenda-none">Nothing planned. Enjoy it.</li>';
  };

  offsets.forEach(d => {
    const date = dayAt(d);
    const weekday = date.toLocaleDateString(undefined, { weekday: 'narrow' });
    const s = document.createElement('span');
    s.innerHTML = `<small>${weekday}</small>${date.getDate()}`;
    days.append(s);
    const b = document.createElement('button');
    b.type = 'button';
    b.dataset.day = d;
    b.setAttribute('aria-label', date.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' }));
    b.innerHTML = `<small>${weekday}</small>${date.getDate()}`;
    b.addEventListener('click', () => show(d));
    pick.append(b);
  });
  show(0);
}
function clocks() {
  const now = new Date();
  $('[data-clock]').textContent = now.toLocaleString(undefined, { weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
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
  let interacted = false, keyboardMove = false;
  const hint = $('.prop-hint', desk);
  // A tap does the same as a drag, and on a phone it's the shorter reach.
  const upHint = matchMedia('(pointer: coarse)').matches ? 'Tap a file to put it on the shelf ↑' : hint.textContent;
  hint.textContent = upHint;

  // Once something is on the shelf, the hint points the other way: taking files back out
  // is the half of the shelf a first drop does not show.
  function updateHint() {
    const held = $$('.shelf-item[data-file]', zone).length;
    const text = held === 0 ? upHint
      : held === 1 ? 'Drag it back down when you need it ↓'
      : 'Drag them back down when you need them ↓';
    if (hint.textContent === text) return;
    hint.textContent = text;
    if (!reduced) animate(hint, { opacity: [0, 1], y: [4, 0], duration: 350, ease: 'out(3)' });
  }

  function overNotch(x, y) {
    const r = notch.getBoundingClientRect();
    return x > r.left - 30 && x < r.right + 30 && y < r.bottom + 40;
  }
  function land(file) {
    const icon = $('.file-icon', file).cloneNode(true);
    const item = document.createElement('div');
    item.className = 'shelf-item';
    item.dataset.file = file.dataset.file;
    item.append(icon, document.createTextNode(file.dataset.file));
    zone.append(item);
    dragOut(item, file);
    zone.classList.add('has-items');
    file.classList.add('gone');
    file.classList.remove('lifted');
    const r = item.getBoundingClientRect();
    burst(r.left + r.width / 2, r.top + 24);
    if (!reduced) animate(item, { scale: [0.6, 1], opacity: [0, 1], duration: 600, ease: 'out(4)' });
    // The keyboard can't reach the notch to take a file back, so it gets the button sooner.
    if (keyboardMove || $$('.file:not(.gone)', desk).length === 0) addReset();
    updateHint();
    if (keyboardMove) {
      keyboardMove = false;
      ($('.file:not(.gone)', desk) ?? $('.put-back', desk))?.focus();
    }
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
      updateHint();
    };
    desk.append(b);
  }

  // Files come back out the way they went in. Drag one off the shelf and let go anywhere
  // but the notch, and it goes back to its place on the desk; let go on the notch and it
  // stays. Visitors try this without being asked: taking things back out is half of
  // what a shelf is for.
  function dragOut(item, file) {
    let sx, sy, lastX, ghost = null;
    item.addEventListener('pointerdown', e => {
      if (ghost) return;
      interacted = true;
      e.preventDefault();
      sx = lastX = e.clientX; sy = e.clientY;
      item.setPointerCapture(e.pointerId);
      // The ghost is the desk-sized file, centred on the shelf icon it was picked up from.
      const r = item.getBoundingClientRect();
      ghost = document.createElement('div');
      ghost.className = 'file-ghost';
      ghost.innerHTML = file.innerHTML;
      Object.assign(ghost.style, { left: `${r.left + r.width / 2 - 48}px`, top: `${r.top - 8}px`, width: '96px' });
      document.body.append(ghost);
      item.classList.add('lifted');
      animate(ghost, { scale: [0.8, 1.08], duration: 200, ease: 'out(3)' });
    });
    item.addEventListener('pointermove', e => {
      if (!ghost) return;
      const dx = e.clientX - sx, dy = e.clientY - sy;
      const tilt = Math.max(-10, Math.min(10, (e.clientX - lastX) * 0.8));
      lastX = e.clientX;
      ghost.style.transform = `translate(${dx}px, ${dy}px) scale(1.08) rotate(${tilt}deg)`;
      zone.classList.toggle('hot', overNotch(e.clientX, e.clientY));
    });
    const end = e => {
      if (!ghost) return;
      const g = ghost; ghost = null;
      zone.classList.remove('hot');
      const m = g.style.transform.match(/translate\(([-\d.]+)px, ([-\d.]+)px\)/);
      const at = m ? { x: +m[1], y: +m[2] } : { x: 0, y: 0 };
      g.style.transform = '';
      animate(g, { x: at.x, y: at.y, scale: 1.08, duration: 0 });
      if (overNotch(e.clientX, e.clientY)) {
        // Dropped back on the notch: it springs back onto the shelf.
        animate(g, { x: 0, y: 0, rotate: 0, scale: 0.8, duration: reduced ? 0 : 450, ease: 'out(4)',
          onComplete: () => { g.remove(); item.classList.remove('lifted'); } });
        return;
      }
      // Anywhere else: home to its own place on the desk, as "Put the files back" does.
      const from = g.getBoundingClientRect(), to = file.getBoundingClientRect();
      const home = { x: at.x + to.left - from.left - (from.width - to.width) / 2, y: at.y + to.top - from.top - (from.height - to.height) / 2 };
      item.remove();
      zone.classList.toggle('has-items', !!$('.shelf-item', zone));
      $('.put-back', desk)?.remove();
      updateHint();
      animate(g, { x: home.x, y: home.y, rotate: 0, scale: 1, duration: reduced ? 0 : 600, ease: 'out(4)',
        onComplete: () => { g.remove(); file.classList.remove('gone', 'lifted'); } });
    };
    item.addEventListener('pointerup', end);
    item.addEventListener('pointercancel', end);
    // An interrupted drag (the window loses focus, the page resizes) can end without a
    // pointerup; without this the ghost would hang in mid-air.
    item.addEventListener('lostpointercapture', end);
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
    let sx, sy, lastX, ghost = null, moved = false;
    file.addEventListener('keydown', e => {
      if (e.key !== 'Enter' && e.key !== ' ') return;
      e.preventDefault();
      if (ghost) return;
      interacted = keyboardMove = true;
      drop(file, lift(file).ghost, true);
    });
    file.addEventListener('pointerdown', e => {
      interacted = true;
      moved = false;
      sx = lastX = e.clientX; sy = e.clientY;
      file.setPointerCapture(e.pointerId);
      ({ ghost } = lift(file));
      animate(ghost, { scale: 1.08, duration: 200, ease: 'out(3)' });
    });
    file.addEventListener('pointermove', e => {
      if (!ghost) return;
      const dx = e.clientX - sx, dy = e.clientY - sy;
      if (Math.abs(dx) + Math.abs(dy) > 8) moved = true;
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
      // A tap counts as "put it on the shelf": on a phone the notch is a long reach.
      drop(file, g, (e.type === 'pointerup' && !moved) || overNotch(e.clientX, e.clientY));
      N.dragView = null;
      render();
    };
    file.addEventListener('pointerup', end);
    file.addEventListener('pointercancel', end);
    // As for shelf items: an interrupted drag still ends.
    file.addEventListener('lostpointercapture', end);
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

let addClip = () => {};

function clipboard() {
  const list = $('[data-cliplist]');
  const colours = { 'This page': '#b9a8ff', Notes: '#ffd60a', Figma: '#a259ff', Terminal: '#8e8e93', Mail: '#0a84ff', Safari: '#30d158', Messages: '#34c759' };
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

  addClip = (text, app) => {
    // A new copy lands in the whole history, not in whatever was last searched for.
    const search = $('[data-clipsearch]');
    if (search.value) { search.value = ''; search.dispatchEvent(new Event('input')); }
    const li = row(text, app);
    list.prepend(li);
    // Three show; older ones stay findable, which is the point of a history.
    while ($$('li:not(.none)', list).length > 8) $$('li:not(.none)', list).pop().remove();
    number();
    if (!reduced) animate(li, { opacity: [0, 1], y: [-10, 0], duration: 500, ease: 'out(3)' });
  };

  // Only the notch's list changes. The visitor's real clipboard is theirs; nothing in a
  // demo should replace what they had on it.
  $$('[data-copy]').forEach(b => b.addEventListener('click', () => {
    addClip(b.dataset.copy.replace(/^https:\/\//, ''), b.dataset.app);
    b.textContent = 'Copied';
    b.classList.add('done');
    setTimeout(() => { b.textContent = 'Copy'; b.classList.remove('done'); }, 1400);
  }));

  const q = $('[data-clipquery]');
  $('[data-clipsearch]').addEventListener('input', e => {
    const v = e.target.value.trim().toLowerCase();
    q.textContent = v || 'Type to search';
    q.parentElement.classList.toggle('typing', !!v);
    list.classList.toggle('searching', !!v);
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
    $('[data-keystatus]').textContent = `${what === 'vol' ? 'Volume' : 'Brightness'} ${Math.round(levels[what] * 100)}%`;
    flash({ state: 'hud' }, 1500);
    const cap = $(`[data-key="${kind}"]`);
    cap?.classList.add('down');
    setTimeout(() => cap?.classList.remove('down'), 110);
  };
  $$('[data-key]').forEach(k => k.addEventListener('click', () => press(k.dataset.key)));
  addEventListener('keydown', e => {
    // Only from a focused key: arrow keys are how people scroll, and this page mustn't
    // take them away part-way down.
    if (!e.target.closest?.('[data-key]')) return;
    const map = { ArrowUp: 'vol-up', ArrowDown: 'vol-down', ArrowRight: 'bright-up', ArrowLeft: 'bright-down' };
    if (map[e.key]) { e.preventDefault(); press(map[e.key]); }
  });
}

// ------------------------------------------------------------------ little things

const little = {
  caffeine: {
    banner: { lead: '<svg viewBox="0 0 24 24" style="color:#ffd479"><use href="#i-cup"/></svg>Awake', trail: '<span data-count>59:59</span>' },
    caption: 'Keep your Mac awake for an hour, or until you turn it off.',
  },
  airpods: {
    banner: { lead: '<svg viewBox="0 0 24 24"><use href="#i-airpods"/></svg>AirPods Pro', trail: '82%<span class="ring" style="--p:.82"></span>' },
    caption: 'Pop them in, see the battery. One honest number.',
  },
  charging: {
    banner: { lead: '<svg viewBox="0 0 24 24" style="color:#32d74b"><use href="#i-bolt"/></svg>Charging', trail: '84%<span class="ring" style="--p:.84"></span>' },
    caption: 'Plug in, it tells you. Unplug, same.',
  },
  mirror: { view: 'mirror', caption: 'See yourself before the meeting starts.' },
};
let littleTab = 'caffeine', countdown;
function applyLittle() {
  const t = little[littleTab];
  body.classList.toggle('awake', littleTab === 'caffeine');
  $('[data-littleprop]').classList.toggle('no-loupe', littleTab === 'mirror');
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
  $$('[data-little]').forEach(x => x.setAttribute('aria-pressed', String(x === b)));
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

// Writes to the clipboard, or, where the browser refuses, selects the text so ⌘C will do.
async function copyOrSelect(text, code, button) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    const range = document.createRange();
    range.selectNodeContents(code);
    getSelection().removeAllRanges();
    getSelection().addRange(range);
    button.textContent = 'Press ⌘C';
    setTimeout(() => (button.textContent = 'Copy'), 6000);
    return false;
  }
}

// What happens once the line is on the clipboard. It lands in the notch's clipboard, the
// behaviour chapter 3 just taught, and the steps stop on the one the visitor is now doing.
function lineCopied(text) {
  addClip(text.replace(/https:\S+\/(install\.sh)/, '…/$1'), 'This page');
  peek('clip');
  holdSteps();
  const next = $('[data-copiednext]');
  next.hidden = false;
  if (!reduced) animate(next, { opacity: [0, 1], y: [-6, 0], duration: 450, ease: 'out(3)' });
}
let holdSteps = () => {};

function install() {
  $$('[data-copytext]').forEach(b => b.addEventListener('click', async () => {
    const code = b.previousElementSibling;
    if (!await copyOrSelect(code.textContent, code, b)) return;
    b.textContent = 'Copied';
    b.classList.add('done');
    const r = b.getBoundingClientRect(); burst(r.left + r.width / 2, r.top + r.height / 2, 30);
    setTimeout(() => { b.textContent = 'Copy'; b.classList.remove('done'); }, 1600);
    // A web page can't open Terminal with the line typed in (browsers block that, rightly),
    // so the next best thing: say exactly what to press next, right under the button.
    if ('next' in b.dataset) lineCopied(code.textContent);
  }));

  // Homebrew copies its command, and says so.
  const brew = $('[data-brew]');
  brew.addEventListener('click', async () => {
    const label = $('[data-brewlabel]');
    try { await navigator.clipboard.writeText(brew.dataset.brew); label.textContent = 'Copied — paste it in Terminal'; }
    catch { label.textContent = brew.dataset.brew; }
    brew.classList.add('done');
    setTimeout(() => { label.textContent = 'Use Homebrew? Copy the brew command'; brew.classList.remove('done'); }, 2600);
  });

  // The three steps play in turn: the copy button gets clicked, Spotlight finds Terminal,
  // Return is pressed and the notch says hello. Once, each time they come into view:
  // someone deciding whether to trust a command shouldn't have to read it past a loop.
  const box = $('[data-steps]');
  const steps = $$('.step', box);
  const typed = $('[data-s2]', box);
  if (reduced) { steps.forEach(s => s.classList.add('active')); steps[1].classList.add('found'); typed.textContent = 'Terminal'; steps[2].classList.add('done'); return; }
  let run = 0, held = false;
  holdSteps = () => {
    held = true;
    run++;
    steps.forEach(s => s.classList.remove('active', 'clicked', 'found', 'pressed', 'done'));
    steps[0].classList.add('clicked');
    steps[1].classList.add('active', 'found');
    typed.textContent = 'Terminal';
  };
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
    steps[2].classList.add('done');
  }
  let played = false;
  new IntersectionObserver(([e]) => {
    if (!e.isIntersecting) { if (!steps[2].classList.contains('done')) { run++; played = false; } return; }
    if (held || played) return;
    played = true;
    play();
  }, { threshold: 0.35 }).observe(box);
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
  // The hero's words for this visitor were set before the first paint (the inline script
  // after the hero in index.html); here the buttons get their behaviour.
  if (document.documentElement.dataset.mac !== 'yes') {
    sendToMac(dl, label);
    seeHowItWorks($('.hero .btn-ghost'));
    return;
  }
  installWithOneLine($('.hero .btn-ghost'));
  afterDownload();
  welcomeBack();
  // At the end of the page the button does the job, rather than sending people back to it.
  $('[data-closecta]').addEventListener('click', e => { e.preventDefault(); oneLine('closing'); });
  dl.addEventListener('click', () => {
    const r = dl.getBoundingClientRect(); burst(r.left + 32, r.top + r.height / 2, 44);
    dl.classList.add('downloading');
    label('Starting download…');
    setTimeout(() => { dl.classList.remove('downloading'); label('Check your Downloads'); }, 1600);
    setTimeout(() => label('Download for Mac'), 6500);
  });
}

// ------------------------------------------------------------------ install paths

// The hero's second button. On a Mac it's the smoothest install (Terminal, no security
// prompt); elsewhere it takes people into the tour, since they can't install anyway.
function installWithOneLine(button) {
  button.addEventListener('click', e => {
    e.preventDefault();
    const r = button.getBoundingClientRect(); burst(r.left + 34, r.top + r.height / 2, 30);
    const text = $('.roll span', button);
    const was = text.textContent;
    text.textContent = 'Line copied';
    setTimeout(() => (text.textContent = was), 3000);
    oneLine('hero');
  });
}

function seeHowItWorks(button) {
  button.addEventListener('click', e => {
    e.preventDefault();
    track('see_how', 'hero');
    $('#features').scrollIntoView({ behavior: reduced ? 'auto' : 'smooth' });
  });
}

// Copies the Terminal line, goes to the install steps and shows what to do next.
async function oneLine(from) {
  const code = $('.cmd.big code');
  const copy = $('.cmd.big [data-copytext]');
  const copied = await copyOrSelect(code.textContent, code, copy);
  track('copy_curl', from);
  // To the line itself, not the top of the section, so on a short window the instructions
  // under it are on screen too.
  $('.cmd.big').scrollIntoView({ behavior: reduced ? 'auto' : 'smooth', block: 'center' });
  if (!copied) return;
  copy.textContent = 'Copied';
  copy.classList.add('done');
  setTimeout(() => { copy.textContent = 'Copy'; copy.classList.remove('done'); }, 2400);
  // Once the scroll has arrived, so the visitor is looking when it lands.
  setTimeout(() => lineCopied(code.textContent), reduced ? 0 : 900);
}

// Opened from the link they sent themselves: they've seen the tour. Go straight to the
// line, and say it was expected.
function welcomeBack() {
  if (new URLSearchParams(location.search).get('ref') !== 'sent') return;
  $('[data-installlede]').textContent = 'Welcome back. Your line’s ready.';
  requestAnimationFrame(() => $('#install').scrollIntoView({ behavior: 'instant', block: 'start' }));
}

// After a disk-image download starts: what to do with it, including the one-time
// security prompt, and the Terminal line as the way around that prompt.
function afterDownload() {
  const sheet = document.createElement('dialog');
  sheet.className = 'fb-dialog dl-sheet';
  sheet.setAttribute('aria-labelledby', 'dl-title');
  sheet.innerHTML = `
    <div class="fb-head"><h2 id="dl-title">Downloading NotchFun</h2><button class="fb-close" type="button" aria-label="Close">×</button></div>
    <div class="fb-body">
      <ol class="dl-steps">
        <li>Open <b>NotchFun.dmg</b> from your Downloads.</li>
        <li>Drag <b>NotchFun</b> into <b>Applications</b>, then open it.</li>
        <li>macOS stops it the first time. Click <b>Done</b>, not Move to Trash, then go to <b>System Settings → Privacy &amp; Security</b>, click <b>Open Anyway</b> and confirm. <a href="#faq-warning" data-help="faq">Why?</a></li>
      </ol>
      <div class="dl-alt">
        <p>Rather skip that step? One line in Terminal installs it without System Settings.</p>
        <button class="send-btn" type="button" data-help="oneline"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4.5 6.5 9 11l-4.5 4.5M11.5 17h8"/></svg><span>Install with one line instead</span></button>
      </div>
    </div>`;
  document.body.append(sheet);
  $('.fb-close', sheet).addEventListener('click', () => sheet.close());
  sheet.addEventListener('click', e => { if (e.target === sheet) sheet.close(); });
  let switched = false;
  $('[data-help="oneline"]', sheet).addEventListener('click', () => { switched = true; track('dl_help', 'oneline'); sheet.close(); oneLine('after_download'); });
  // The security step comes minutes after this panel closes, so what to do stays on the page.
  sheet.addEventListener('close', () => {
    if (switched || $('.dl-recap')) return;
    const recap = document.createElement('p');
    recap.className = 'dl-recap';
    recap.innerHTML = 'Next: open <b>NotchFun.dmg</b>, drag it to Applications and open it. When macOS stops it, click <b>Done</b>, then <b>System Settings → Privacy &amp; Security → Open Anyway</b>.';
    $('.free-note').after(recap);
    $('.other-ways').after(recap.cloneNode(true));
  });
  $('[data-help="faq"]', sheet).addEventListener('click', e => {
    e.preventDefault();
    track('dl_help', 'faq');
    switched = true;
    sheet.close();
    const faq = $('#faq-warning');
    faq.open = true;
    faq.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth', block: 'center' });
  });
  // The download carries on underneath; the panel opens a moment later.
  $$('[data-dl]').forEach(a => a.addEventListener('click', () => setTimeout(() => sheet.open || sheet.showModal(), 700)));
}

// ------------------------------------------------------------------ send to my Mac

const SEND_URL = 'https://lookatsarthak.github.io/NotchFun/?ref=sent';
const SEND_TEXT = 'NotchFun turns the MacBook notch into a home for music, files and your clipboard. Open this on your Mac to install it.';
const sentOnce = new Set();
const trackSend = c => { if (!sentOnce.has(c)) { sentOnce.add(c); track('send_mac', c); } };

function sendToMac(button, label) {

  const sheet = document.createElement('dialog');
  sheet.className = 'fb-dialog send-sheet';
  sheet.setAttribute('aria-labelledby', 'send-title');
  sheet.innerHTML = `
    <div class="fb-head"><h2 id="send-title">Send it to your Mac</h2><button class="fb-close" type="button" aria-label="Close">×</button></div>
    <div class="fb-body">
      <p class="send-lede">NotchFun runs on Macs with macOS 26 or later. Send yourself the link and open it there.</p>
      <div class="send-actions">
        <label class="fb-field send-field"><span class="fb-label">Your email <small>fills in the To line</small></span>
          <input type="email" name="send-to" autocomplete="email" inputmode="email" autocapitalize="off" spellcheck="false" placeholder="you@example.com"></label>
        <a class="send-btn" data-send="email" href="#">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3.5 6.5h17v11h-17zM3.5 7l8.5 6.5L20.5 7"/></svg><span>Open in my mail app</span></a>
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
  email.addEventListener('click', () => { email.href = mailto(); trackSend('email'); });
  $('[data-send="copy"]', sheet).addEventListener('click', async e => {
    const b = e.currentTarget;
    try { await navigator.clipboard.writeText(SEND_URL); $('span', b).textContent = 'Link copied'; }
    catch { $('span', b).textContent = SEND_URL; }
    trackSend('copy');
  });

  // Phones and tablets get their own share sheet (AirDrop, Messages, Mail). Only the link
  // is shared: with text alongside, AirDrop can arrive on the Mac as a note instead of
  // opening the page, and Messages shows the link's preview card anyway. Desktops get the
  // panel: a Windows share sheet can't reach a Mac.
  const touch = matchMedia('(pointer: coarse)').matches;
  const send = async e => {
    e?.preventDefault();
    trackSend('open');
    const data = { title: 'NotchFun', url: SEND_URL };
    if (touch && navigator.share && (!navigator.canShare || navigator.canShare(data))) {
      try {
        await navigator.share(data);
        trackSend('share');
        label('Sent. Open it on your Mac');
        setTimeout(() => label('Send to my Mac'), 5000);
        return;
      } catch (err) {
        if (err?.name === 'AbortError') return; // they closed the share sheet
      }
    }
    sheet.showModal();
  };
  button.addEventListener('click', e => { const r = button.getBoundingClientRect(); burst(r.left + 32, r.top + r.height / 2, 30); send(e); });

  // The round button in the phone's menu bar does the same, with the same icon.
  $('.mb-download')?.addEventListener('click', send);

  // The install steps are for the Mac; say so, and offer the same way across.
  const box = $('.install-box');
  if (box) {
    const note = document.createElement('div');
    note.className = 'send-note';
    note.innerHTML = '<p><b>You\u2019re not on a Mac right now.</b> These steps are for your Mac, so send yourself the link and do them there.</p><button type="button" class="send-btn" data-send="note"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M21 3 10.5 13.5M21 3l-6.5 18-4-7.5L3 9.5z"/></svg><span>Send to my Mac</span></button>';
    box.prepend(note);
    $('button', note).addEventListener('click', send);
  }

  // The same at the end of the page.
  const close = $('[data-closecta]');
  $('.roll', close).dataset.label = 'Send to my Mac';
  $('.roll span', close).textContent = 'Send to my Mac';
  close.href = '#send';
  close.addEventListener('click', send);

  // On a phone the one useful action stays under the thumb, except where one is already
  // on screen.
  const bar = document.createElement('button');
  bar.type = 'button';
  bar.className = 'send-bar';
  bar.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M21 3 10.5 13.5M21 3l-6.5 18-4-7.5L3 9.5z"/></svg><span>Send to my Mac</span>';
  bar.addEventListener('click', send);
  body.append(bar);
  const covering = new Set();
  const io = new IntersectionObserver(entries => {
    // The hero's buttons have scrolled away well before its last pixels have.
    entries.forEach(e => (e.isIntersecting && (e.target !== heroEl || e.intersectionRatio > 0.3) ? covering.add(e.target) : covering.delete(e.target)));
    bar.classList.toggle('show', covering.size === 0);
  }, { threshold: [0, 0.3] });
  [heroEl, $('.send-note'), $('[data-closing]')].forEach(el => el && io.observe(el));
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
  // A hung request would leave "Loading…" up forever, so each gets a few seconds.
  const signal = () => AbortSignal.timeout(6000);
  let res = await fetch(`${API}/gh/${path ? 'releases' : 'repo'}`, { signal: signal() }).catch(() => null);
  if (!res?.ok) res = await fetch(`https://api.github.com/repos/${REPO}${path}`, { signal: signal(), headers: { Accept: 'application/vnd.github+json' } });
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
    const releases = (await gh('/releases?per_page=6')).filter(r => !r.draft && !r.prerelease).slice(0, 1);
    box.innerHTML = '';
    // Only the latest: the rest is one link away, and this page is selling, not archiving.
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
  } catch {
    box.innerHTML = '<p class="loading">Couldn\'t reach GitHub just now.</p>';
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
  wrap.classList.add('ready');
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

// ------------------------------------------------------------------ real footage

// "Try it" or "Watch the real app": the recording replaces the demo in place, and only
// plays while it is showing.
function propSwitches() {
  $$('[data-prop]').forEach(prop => {
    const video = $('video', prop);
    $$('[data-show]', prop).forEach(b => b.addEventListener('click', () => {
      const show = b.dataset.show;
      $$('[data-show]', prop).forEach(x => x.setAttribute('aria-pressed', String(x === b)));
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

// ------------------------------------------------------------------ FAQ

// A link to a question opens it; arriving at a closed answer isn't an answer.
function faqLinks() {
  const open = () => {
    const el = location.hash && document.getElementById(location.hash.slice(1));
    if (el?.tagName === 'DETAILS') el.open = true;
  };
  addEventListener('hashchange', open);
  open();
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
propSwitches();
buttons();
counts();
feedbackDialog();
faqLinks();
closingHello();
dock();
render();
introHero();
playHello().then(tour);
window.nfBooted = true;
