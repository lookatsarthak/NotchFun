// NotchFun's backend (worker/ in the repo): feedback, and anonymous counts.
//
// What the site counts: page views with the referring site, the install section being
// seen, and clicks on download, copy, star and feedback. No cookies, nothing stored that
// identifies you. Visiting with ?notrack turns it off on this browser for good, and the
// browser's Do Not Track setting is honoured.

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
  if (noTrack) return;
  try {
    navigator.sendBeacon(`${API}/e`, new Blob([JSON.stringify({ e: event, c: channel })], { type: 'text/plain' }));
  } catch { /* counting is never worth an error */ }
}

// Download links point at the backend, which counts the click and hands over the GitHub
// file. The maintainer's own clicks (with ?notrack) are passed through uncounted.
export function downloadURL(channel) {
  return `${API}/d/${channel}${noTrack ? '?nt=1' : ''}`;
}
