// How visitors use the page, counted anonymously so the maintainer can see where interest
// fades and what people try. Each kind of thing is counted at most once per page load,
// so the numbers read as "how many visits did X". No cookies, no stored identifiers; see
// api.js for the opt-out.

import { track, trackMany, noTrack } from './api.js';

const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const sent = new Set();
const once = (event, channel = '') => {
  const key = `${event}|${channel}`;
  if (sent.has(key)) return;
  sent.add(key);
  track(event, channel);
};

/** Called once the page is set up. `view` is the referring site, sent with the visit. */
export function insights(from) {
  if (noTrack) return;
  trackMany([['view', from], ['device', device()], ['lang', language()]]);
  sections();
  clicks();
  timeOnPage();
}

// ------------------------------------------------------------------ who

function device() {
  const ua = navigator.userAgent;
  const touch = navigator.maxTouchPoints > 1;
  const os = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && touch) ? 'ios'
    : /Macintosh|Mac OS X/.test(ua) ? 'mac'
    : /Android/.test(ua) ? 'android'
    : /Windows/.test(ua) ? 'windows'
    : /Linux|CrOS/.test(ua) ? 'linux' : 'other';
  const short = Math.min(screen.width, screen.height);
  const form = !touch ? 'desktop' : short < 600 ? 'phone' : 'tablet';
  return `${os}/${form}`;
}

const language = () => (navigator.language || '').toLowerCase().split('-')[0].replace(/[^a-z]/g, '').slice(0, 3) || 'other';

// ------------------------------------------------------------------ how far

// A section counts as seen when a good part of it has been on screen: 30% of it, or half
// the window for sections taller than the window.
function sections() {
  const named = [
    // section[…], because <body> carries data-chapter too (the chapter on screen).
    ['[data-hero]', 'hero'], ...$$('section[data-chapter]').map(el => [el, el.dataset.chapter]),
    ['#native', 'native'], ['#install', 'install'], ['#changelog', 'changelog'],
    ['#community', 'community'], ['.faq', 'faq'], ['.foot', 'footer'],
  ];
  const nameOf = new Map();
  const io = new IntersectionObserver(entries => entries.forEach(e => {
    if (!e.isIntersecting) return;
    if (e.intersectionRatio >= 0.3 || e.intersectionRect.height >= innerHeight * 0.5) {
      once('section', nameOf.get(e.target));
      io.unobserve(e.target);
    }
  }), { threshold: [0, 0.15, 0.3, 0.5, 0.75, 1] });
  for (const [target, name] of named) {
    const el = typeof target === 'string' ? document.querySelector(target) : target;
    if (!el) continue;
    nameOf.set(el, name);
    io.observe(el);
  }
}

// ------------------------------------------------------------------ what they try

const FAQ = ['free', 'warning', 'macs', 'permissions', 'privacy'];

function outbound(href) {
  let url;
  try { url = new URL(href, location.href); } catch { return null; }
  if (url.origin === location.origin) return null;
  const path = url.pathname;
  if (url.hostname !== 'github.com' && url.hostname !== 'raw.githubusercontent.com') return 'other';
  if (/install\.sh$/.test(path)) return 'install_script';
  if (/\/releases/.test(path)) return 'releases';
  if (/\/issues/.test(path)) return 'issues';
  if (/LICENSE/i.test(path)) return 'license';
  if (/CONTRIBUTING/i.test(path)) return 'contributing';
  return 'github';
}

function clicks() {
  const chapterOf = el => el.closest('section[data-chapter]')?.dataset.chapter;

  document.addEventListener('click', e => {
    const t = e.target instanceof Element ? e.target : null;
    if (!t) return;

    const show = t.closest('[data-show]');
    if (show && chapterOf(show)) once('toggle', `${chapterOf(show)}:${show.dataset.show}`);

    const act = t.closest('[data-act]');
    if (act) once('demo', `music:${act.dataset.act}`);
    const little = t.closest('[data-little]');
    if (little) once('demo', `little:${little.dataset.little}`);
    if (t.closest('[data-key]')) once('demo', 'keys:press');
    if (t.closest('[data-copy]')) once('demo', 'clip:copy');

    const summary = t.closest('.faq summary');
    if (summary && !summary.parentElement.open) {
      const i = $$('.faq details').indexOf(summary.parentElement);
      if (FAQ[i]) once('faq_open', FAQ[i]);
    }
    if (t.closest('.release .more, button.more')) once('changelog_more');

    // Star links are counted as star_click already (main.js).
    const a = t.closest('a[href]');
    if (a && !a.hasAttribute('data-starfrom') && !a.hasAttribute('data-dl')) {
      const where = outbound(a.getAttribute('href'));
      if (where) once('outbound', where);
    }
  }, { capture: true });

  document.addEventListener('pointerdown', e => {
    if (e.target instanceof Element && e.target.closest('.file')) once('demo', 'shelf:drag');
  }, { capture: true });
  document.addEventListener('input', e => {
    if (!(e.target instanceof Element)) return;
    if (e.target.matches('[data-clipsearch]')) once('demo', 'clip:search');
    if (e.target.matches('[data-width]')) once('demo', 'native:width');
  }, { capture: true });
  // Keyboard presses in the volume chapter count like clicks on its keys.
  addEventListener('keydown', e => {
    if (document.body.dataset.chapter === 'keys' && ['F1', 'F2', 'F11', 'F12', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key)) once('demo', 'keys:press');
  });

  $$('[data-prop] video').forEach(v => v.addEventListener('ended', () => { const c = chapterOf(v); if (c) once('video_end', c); }));
}

// ------------------------------------------------------------------ how long

// Time the page was actually visible, reported once, when it is first hidden or left.
function timeOnPage() {
  let visibleSince = document.visibilityState === 'visible' ? performance.now() : null;
  let total = 0;
  const bucket = ms => (ms < 10e3 ? '<10s' : ms < 30e3 ? '10-30s' : ms < 120e3 ? '30s-2m' : ms < 300e3 ? '2-5m' : '5m+');
  const report = () => {
    if (visibleSince !== null) { total += performance.now() - visibleSince; visibleSince = null; }
    once('time', bucket(total));
  };
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') report();
    else visibleSince = performance.now();
  });
  addEventListener('pagehide', report);
}
