// NotchFun's backend (worker/ in the repo): feedback, and anonymous counts.
//
// What the site counts (insights.js has the details): page views with the referring site,
// how far down the page people get, what they click and try, rough device type, language
// and time on page, and clicks on download, copy, star and feedback. Everything is a
// count. No cookies, nothing stored that identifies you. Visiting with ?notrack turns it
// off on this browser for good, and the browser's Do Not Track setting is honoured.

const LIVE = location.hostname === 'lookatsarthak.github.io';

export const API = LIVE ? 'https://notchfun.lookatsarthak.workers.dev' : 'http://127.0.0.1:8787';
// Off the real site, Cloudflare's test key, which always passes without showing anything.
export const TURNSTILE_SITEKEY = LIVE ? '0x4AAAAAAFM1evCblBTBJiE4' : '1x00000000000000000000BB';

export const noTrack = (() => {
  try {
    if (new URLSearchParams(location.search).has('notrack')) localStorage.setItem('nf-notrack', '1');
    return localStorage.getItem('nf-notrack') === '1' || navigator.doNotTrack === '1';
  } catch {
    return navigator.doNotTrack === '1';
  }
})();

export function track(event, channel = '') {
  send({ e: event, c: channel });
}

/** Several events in one request: [[event, channel], ...], at most 12. */
export function trackMany(events) {
  send({ b: events.map(([e, c = '']) => ({ e, c })) });
}

function send(body) {
  if (noTrack) return;
  try {
    navigator.sendBeacon(`${API}/e`, new Blob([JSON.stringify(body)], { type: 'text/plain' }));
  } catch { /* counting is never worth an error */ }
}

// Download links point at the backend, which counts the click and hands over the GitHub
// file. The maintainer's own clicks (with ?notrack) are passed through uncounted.
export function downloadURL(channel) {
  return `${API}/d/${channel}${noTrack ? '?nt=1' : ''}`;
}
