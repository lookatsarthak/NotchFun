// End-to-end checks against a running Worker (`npm run dev` first). Uses the local
// database, which these tests empty at the start. Run with `npm test`.
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

const BASE = process.env.API ?? 'http://127.0.0.1:8787';
const SITE = 'https://lookatsarthak.github.io';
const ADMIN = process.env.ADMIN_TOKEN ?? 'local-dev-admin';
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15';

const get = (path, headers = {}) => fetch(BASE + path, { redirect: 'manual', headers: { 'user-agent': UA, ...headers } });
const post = (path, body, headers = {}) => fetch(BASE + path, { method: 'POST', body: typeof body === 'string' ? body : JSON.stringify(body), headers: { 'user-agent': UA, origin: SITE, ...headers } });
const stats = async () => (await get('/stats', { authorization: `Bearer ${ADMIN}` })).json();
const total = (s, event, channel) => s.totals.filter(t => t.event === event && (channel === undefined || t.channel === channel)).reduce((a, t) => a + t.n, 0);
// Counting runs after the response is sent, so give it a moment.
const settle = () => new Promise(r => setTimeout(r, 300));

before(() => {
  execFileSync('npx', ['wrangler', 'd1', 'execute', 'notchfun', '--local', '--command',
    'DELETE FROM counts; DELETE FROM visitors; DELETE FROM salts; DELETE FROM feedback; DELETE FROM limits; DELETE FROM snapshots; DELETE FROM journeys;'], { stdio: 'ignore' });
});

test('download buttons redirect to the latest disk image and count by channel', async () => {
  const res = await get('/d/hero');
  assert.equal(res.status, 302);
  assert.equal(res.headers.get('location'), 'https://github.com/lookatsarthak/NotchFun/releases/latest/download/NotchFun.dmg');
  await get('/d/install');
  await get('/d/somewhere-odd');
  await get('/d/hero?nt=1'); // the maintainer's own clicks
  assert.equal((await fetch(BASE + '/d/hero', { method: 'HEAD', redirect: 'manual' })).status, 302, 'HEAD redirects too…');
  await settle();
  const s = await stats();
  assert.equal(total(s, 'dmg', 'hero'), 1, '…but only GET is counted');
  assert.equal(total(s, 'dmg', 'install'), 1);
  assert.equal(total(s, 'dmg', 'other'), 1);
});

test('Homebrew redirects to that exact version and counts it', async () => {
  const res = await get('/brew/1.6.1');
  assert.equal(res.status, 302);
  assert.equal(res.headers.get('location'), 'https://github.com/lookatsarthak/NotchFun/releases/download/v1.6.1/NotchFun-1.6.1.dmg');
  assert.equal((await get('/brew/..%2F..%2Fevil')).status, 404);
  assert.equal((await get('/brew/latest')).status, 404);
  await get('/brew/1.6.1?nt=1');
  await settle();
  const s = await stats();
  assert.equal(total(s, 'brew'), 1);
  assert.deepEqual(s.versions.filter(v => v.event === 'brew').map(v => v.version), ['1.6.1']);
});

test('install.sh pings: start, success with Mac type, failure with a known reason', async () => {
  assert.equal((await get('/i?s=start&v=1.6.1')).status, 204);
  assert.equal((await get('/i?s=ok&v=1.6.1&a=arm64&m=26')).status, 204);
  assert.equal((await get('/i?s=fail&r=download')).status, 204);
  assert.equal((await get('/i?s=fail&r=<script>')).status, 204);
  assert.equal((await get('/i?s=bogus')).status, 204);
  await settle();
  const s = await stats();
  assert.equal(total(s, 'curl_start'), 1);
  assert.equal(total(s, 'curl_ok', 'arm64/26'), 1);
  assert.equal(total(s, 'curl_fail', 'download'), 1);
  assert.equal(total(s, 'curl_fail', 'other'), 1, 'unknown reasons are filed under other');
});

test('website events: allowed origin only, no bots, known events only, unique visitors', async () => {
  assert.equal((await post('/e', { e: 'view', c: 'www.Reddit.com' })).status, 204);
  assert.equal((await post('/e', { e: 'view', c: 'reddit.com' })).status, 204); // same visitor again
  assert.equal((await post('/e', { e: 'view', c: 'news.ycombinator.com' }, { origin: 'https://evil.example' })).status, 204);
  assert.equal((await post('/e', { e: 'view', c: 'x.com' }, { 'user-agent': 'Googlebot/2.1' })).status, 204);
  assert.equal((await post('/e', { e: 'star_click', c: 'hero' })).status, 204);
  assert.equal((await post('/e', { e: 'star_click', c: 'nowhere' })).status, 400);
  assert.equal((await post('/e', { e: 'drop_tables' })).status, 400);
  assert.equal((await post('/e', 'not json')).status, 400);
  await settle();
  const s = await stats();
  assert.equal(total(s, 'view', 'reddit.com'), 2);
  assert.equal(total(s, 'view'), 2, 'other origins and bots are not counted');
  assert.equal(total(s, 'visitor'), 1);
  assert.equal(total(s, 'star_click', 'hero'), 1);
});

test('feedback: validates, verifies, stores, and ignores the honeypot', async () => {
  const good = { kind: 'bug', message: 'The shelf closes too soon.', email: 'someone@example.com', version: '1.6.1 (24)', os: 'macOS 26.0', source: 'app', token: 'XXXX.DUMMY.TOKEN.XXXX' };
  let res = await post('/feedback', good);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('access-control-allow-origin'), SITE);
  assert.deepEqual(await res.json(), { ok: true });

  assert.equal((await post('/feedback', { ...good, token: '' })).status, 403, 'no Turnstile token');
  assert.equal((await post('/feedback', { ...good, message: 'hi' })).status, 400);
  assert.equal((await post('/feedback', { ...good, message: 'x'.repeat(5001) })).status, 400);
  assert.equal((await post('/feedback', { ...good, email: 'not-an-email' })).status, 400);
  assert.equal((await post('/feedback', good, { origin: 'https://evil.example' })).status, 403);
  res = await post('/feedback', { ...good, website: 'http://spam.example' });
  assert.equal(res.status, 200, 'bots get an ok…');

  await settle();
  const s = await stats();
  assert.equal(s.feedback.length, 1, '…but nothing is kept');
  const [f] = s.feedback;
  assert.equal(f.kind, 'bug');
  assert.equal(f.email, 'someone@example.com');
  assert.equal(f.app_version, '1.6.1 (24)');
  assert.equal(f.macos, '26.0');
  assert.equal(f.source, 'app');
  assert.equal(f.emailed, 0, 'no Resend key locally, so not emailed');
});

test('feedback without an email, and with junk version fields', async () => {
  const res = await post('/feedback', { kind: 'nonsense', message: 'Love it', version: '<b>1</b>', os: 'Windows', token: 't' }, { 'user-agent': 'Another browser' });
  assert.equal(res.status, 200);
  await settle();
  const [f] = (await stats()).feedback;
  assert.equal(f.kind, 'other');
  assert.equal(f.email, null);
  assert.equal(f.app_version, null);
  assert.equal(f.macos, null);
  assert.equal(f.source, 'site');
});

test('feedback is limited to 20 an hour from one visitor', async () => {
  const body = { kind: 'idea', message: 'Rate limit check', token: 't' };
  const headers = { 'user-agent': 'Rate limit browser' };
  const codes = [];
  for (let i = 0; i < 22; i++) codes.push((await post('/feedback', body, headers)).status);
  assert.deepEqual(codes, [...Array(20).fill(200), 429, 429]);
});

test('CORS preflight for the feedback form', async () => {
  const res = await fetch(BASE + '/feedback', { method: 'OPTIONS', headers: { origin: SITE, 'access-control-request-method': 'POST', 'access-control-request-headers': 'content-type' } });
  assert.equal(res.status, 204);
  assert.equal(res.headers.get('access-control-allow-origin'), SITE);
  assert.match(res.headers.get('access-control-allow-headers'), /content-type/);
});

test('stats need the admin token', async () => {
  assert.equal((await get('/stats')).status, 401);
  assert.equal((await get('/stats', { authorization: 'Bearer wrong' })).status, 401);
  assert.equal((await get('/stats', { authorization: `Bearer ${ADMIN}x` })).status, 401);
  assert.equal((await get('/stats', { authorization: `Bearer ${ADMIN}` })).status, 200);
});

test('the daily job copies GitHub numbers and clears old visitor data', async () => {
  execFileSync('npx', ['wrangler', 'd1', 'execute', 'notchfun', '--local', '--command',
    "INSERT INTO visitors (day, hash) VALUES ('2000-01-01', 'old'); INSERT INTO salts (day, salt) VALUES ('2000-01-01', 'old'); INSERT INTO limits (key, hour, n) VALUES ('old', '2000-01-01T00', 1);"], { stdio: 'ignore' });
  const res = await get('/stats?snapshot=1', { authorization: `Bearer ${ADMIN}` });
  assert.equal(res.status, 200);
  const { rows, via } = await res.json();
  // Locally there's no GitHub credential, and GitHub allows only 60 anonymous calls an
  // hour, so the copy itself is only checked when it got through.
  if (rows > 0) {
    const s = await stats();
    // Anonymous calls can run out partway, so only check that what arrived was stored.
    assert.ok(s.github.length > 0);
  } else {
    assert.equal(via, 'none');
  }
  const left = execFileSync('npx', ['wrangler', 'd1', 'execute', 'notchfun', '--local', '--json', '--command',
    "SELECT (SELECT COUNT(*) FROM visitors WHERE day < '2001-01-01') + (SELECT COUNT(*) FROM salts WHERE day < '2001-01-01') + (SELECT COUNT(*) FROM limits WHERE hour < '2001') AS n"]).toString();
  assert.equal(JSON.parse(left)[0].results[0].n, 0);
});

test('admin page and unknown paths', async () => {
  const res = await get('/admin');
  assert.equal(res.status, 200);
  assert.match(await res.text(), /NotchFun numbers/);
  assert.equal((await get('/nope')).status, 404);
});

test('behaviour: batches, allowed events only, once per kind of thing', async () => {
  const ua = { 'user-agent': 'Behaviour browser' };
  assert.equal((await post('/e', { b: [{ e: 'view', c: 'news.ycombinator.com' }, { e: 'device', c: 'mac/desktop' }, { e: 'lang', c: 'en' }] }, ua)).status, 204);
  for (const [e, c] of [['section', 'music'], ['section', 'install'], ['toggle', 'shelf:real'], ['video_end', 'shelf'], ['demo', 'clip:search'],
    ['faq_open', 'warning'], ['outbound', 'releases'], ['time', '30s-2m'], ['changelog_more', '']]) {
    assert.equal((await post('/e', { e, c }, ua)).status, 204, `${e} ${c}`);
  }
  // Refused: unknown channels, unknown events, a batch with one bad event, an oversized batch.
  for (const bad of [{ e: 'section', c: 'basement' }, { e: 'toggle', c: 'music:maybe' }, { e: 'device', c: 'mac/fridge' }, { e: 'lang', c: 'english!' },
    { e: 'time', c: 'forever' }, { e: 'constructor' }, { b: [{ e: 'view', c: '' }, { e: 'nope' }] }, { b: Array(13).fill({ e: 'view', c: '' }) }, { b: [] }]) {
    assert.equal((await post('/e', bad, ua)).status, 400, JSON.stringify(bad).slice(0, 60));
  }
  await settle();
  const s = await stats();
  assert.equal(total(s, 'device', 'mac/desktop'), 1);
  assert.equal(total(s, 'lang', 'en'), 1);
  assert.equal(total(s, 'section', 'music'), 1);
  assert.equal(total(s, 'toggle', 'shelf:real'), 1);
  assert.equal(total(s, 'faq_open', 'warning'), 1);
  assert.equal(total(s, 'outbound', 'releases'), 1);
  assert.equal(total(s, 'time', '30s-2m'), 1);
  assert.equal(total(s, 'section', 'basement'), 0);
  assert.equal(total(s, 'view', 'news.ycombinator.com'), 1, 'nothing from the refused batch was counted');
});

test('funnel: steps from one visitor today, including a download through /d', async () => {
  const ua = { 'user-agent': 'Funnel browser' };
  const before = (await stats()).funnel;
  await post('/e', { b: [{ e: 'view', c: '' }] }, ua);
  await post('/e', { e: 'section', c: 'music' }, ua);
  await post('/e', { e: 'section', c: 'install' }, ua);
  await get('/d/install', ua);
  await settle();
  // Another visitor who only landed.
  await post('/e', { b: [{ e: 'view', c: '' }] }, { 'user-agent': 'Bounce browser' });
  await settle();
  const after = (await stats()).funnel;
  assert.deepEqual(
    Object.fromEntries(Object.keys(after).map(k => [k, after[k] - before[k]])),
    { landed: 2, features: 1, install: 1, action: 1 },
  );
});

test('funnel: finished days roll up into counts and their hashes are deleted', async () => {
  execFileSync('npx', ['wrangler', 'd1', 'execute', 'notchfun', '--local', '--command',
    "INSERT INTO journeys (day, hash, steps) VALUES ('2001-01-01', 'a', 15), ('2001-01-01', 'b', 1), ('2001-01-01', 'c', 3);"], { stdio: 'ignore' });
  await get('/stats?snapshot=1', { authorization: `Bearer ${ADMIN}` });
  const rows = JSON.parse(execFileSync('npx', ['wrangler', 'd1', 'execute', 'notchfun', '--local', '--json', '--command',
    "SELECT channel, n FROM counts WHERE event = 'funnel' AND day = '2001-01-01' ORDER BY channel"]).toString())[0].results;
  assert.deepEqual(Object.fromEntries(rows.map(r => [r.channel, r.n])), { action: 1, features: 2, install: 1, landed: 3 });
  const left = JSON.parse(execFileSync('npx', ['wrangler', 'd1', 'execute', 'notchfun', '--local', '--json', '--command',
    "SELECT COUNT(*) AS n FROM journeys WHERE day < '2002-01-01'"]).toString())[0].results[0].n;
  assert.equal(left, 0);
});

test('maintainer sign-in: emailed one-use link, 90-day cookie, sign out', async () => {
  execFileSync('npx', ['wrangler', 'd1', 'execute', 'notchfun', '--local', '--command',
    "DELETE FROM admin_links; DELETE FROM admin_sessions; DELETE FROM limits WHERE key = 'admin-link';"], { stdio: 'ignore' });
  assert.equal((await get('/stats')).status, 401);
  assert.equal((await fetch(BASE + '/admin/link', { method: 'POST' })).status, 403, 'needs the dashboard as origin');
  const ask = await fetch(BASE + '/admin/link', { method: 'POST', headers: { origin: BASE } });
  assert.equal(ask.status, 200);
  const { link } = await ask.json(); // only returned with DEV=1; production emails it
  const t = new URL(link).searchParams.get('t');

  const landing = await fetch(link);
  assert.equal(landing.status, 200, 'opening the link only shows a button');
  assert.match(await landing.text(), /<form method="post">/);

  const form = new URLSearchParams({ t });
  const login = await fetch(BASE + '/admin/login', { method: 'POST', body: form, redirect: 'manual' });
  assert.equal(login.status, 303);
  const setCookie = login.headers.get('set-cookie');
  assert.match(setCookie, /__Host-nf_admin=[\w-]{43}; Path=\/; Max-Age=7776000; HttpOnly; Secure; SameSite=Strict/);
  const cookie = setCookie.split(';')[0];
  assert.equal((await get('/stats', { cookie })).status, 200);

  assert.equal((await fetch(BASE + '/admin/login', { method: 'POST', body: form, redirect: 'manual' })).status, 400, 'a link works once');
  assert.equal((await fetch(BASE + '/admin/login?t=nope')).status, 400);
  assert.equal((await get('/stats', { cookie: '__Host-nf_admin=forged' })).status, 401);

  assert.equal((await fetch(BASE + '/admin/logout', { method: 'POST', headers: { cookie } })).status, 204);
  assert.equal((await get('/stats', { cookie })).status, 401, 'signed out');

  // At most 3 links an hour.
  const codes = [];
  for (let i = 0; i < 3; i++) codes.push((await fetch(BASE + '/admin/link', { method: 'POST', headers: { origin: BASE } })).status);
  assert.deepEqual(codes, [200, 200, 429]);
});

test('expired links are refused', async () => {
  execFileSync('npx', ['wrangler', 'd1', 'execute', 'notchfun', '--local', '--command',
    "DELETE FROM limits WHERE key = 'admin-link';"], { stdio: 'ignore' });
  const { link } = await (await fetch(BASE + '/admin/link', { method: 'POST', headers: { origin: BASE } })).json();
  execFileSync('npx', ['wrangler', 'd1', 'execute', 'notchfun', '--local', '--command', 'UPDATE admin_links SET expires = 1;'], { stdio: 'ignore' });
  const res = await fetch(BASE + '/admin/login', { method: 'POST', body: new URLSearchParams({ t: new URL(link).searchParams.get('t') }), redirect: 'manual' });
  assert.equal(res.status, 400);
});

test('platforms: tagged on every count, filterable, compared side by side', async () => {
  execFileSync('npx', ['wrangler', 'd1', 'execute', 'notchfun', '--local', '--command',
    'DELETE FROM counts; DELETE FROM journeys; DELETE FROM visitors;'], { stdio: 'ignore' });
  const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1';
  const WIN = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/140.0 Safari/537.36';
  // A Windows visitor who reads to Install; the page says which platform it is.
  await post('/e', { b: [{ e: 'view', c: '' }, { e: 'section', c: 'music' }, { e: 'section', c: 'install' }], p: 'windows/desktop' }, { 'user-agent': WIN });
  // An iPhone visitor whose page didn't say: worked out from the browser.
  await post('/e', { b: [{ e: 'view', c: '' }] }, { 'user-agent': IPHONE });
  // A Mac visitor sending a made-up platform, which is ignored for the browser's own.
  await post('/e', { b: [{ e: 'view', c: '' }, { e: 'section', c: 'music' }], p: 'mac/fridge' }, { 'user-agent': UA });
  await get('/d/hero?p=mac%2Fdesktop');
  await get('/i?s=ok&v=1.6.1&a=arm64&m=26', { 'user-agent': 'curl/8.7.1' });
  await get('/brew/1.6.1', { 'user-agent': 'Homebrew/4.6' });
  await settle();

  const all = await stats();
  const by = Object.fromEntries(all.byPlatform.map(r => [r.platform, r]));
  assert.equal(by['windows/desktop'].visits, 1);
  assert.equal(by['windows/desktop'].install, 1, 'reached Install');
  assert.equal(by['windows/desktop'].action, 0);
  assert.equal(by['ios/phone'].visits, 1);
  assert.equal(by['mac/desktop'].visits, 1);
  assert.equal(by['mac/desktop'].features, 1);
  assert.equal(by['mac/desktop'].action, 1, 'the download was from the same Mac browser');
  assert.equal(by['mac/desktop'].installs, 2, 'Terminal and Homebrew installs are Macs');
  assert.ok(!by['mac/fridge']);

  const win = await (await get('/stats?os=windows', { authorization: `Bearer ${ADMIN}` })).json();
  assert.equal(win.os, 'windows');
  assert.equal(total(win, 'view'), 1);
  assert.equal(total(win, 'dmg'), 0);
  assert.deepEqual(win.funnel, { landed: 1, features: 1, install: 1, action: 0 });
  const mac = await (await get('/stats?os=mac', { authorization: `Bearer ${ADMIN}` })).json();
  assert.equal(total(mac, 'dmg'), 1);
  assert.equal(total(mac, 'curl_ok'), 1);
  const bogus = await (await get('/stats?os=amiga', { authorization: `Bearer ${ADMIN}` })).json();
  assert.equal(bogus.os, null, 'unknown platforms mean all');
  assert.equal(total(bogus, 'view'), 3);
});

test('a preview copy of the site can read GitHub data but never counts or sends feedback', async () => {
  const PREVIEW = 'https://notchfun-preview.lookatsarthak.workers.dev';
  const before = (await stats()).totals.length;
  assert.equal((await post('/e', { b: [{ e: 'lang', c: 'pv' }] }, { origin: PREVIEW })).status, 204);
  assert.equal((await post('/feedback', { kind: 'idea', message: 'from preview', token: 't' }, { origin: PREVIEW })).status, 403);
  const pre = await fetch(BASE + '/feedback', { method: 'OPTIONS', headers: { origin: PREVIEW, 'access-control-request-method': 'GET' } });
  assert.equal(pre.headers.get('access-control-allow-origin'), PREVIEW, 'reads are allowed');
  assert.equal((await fetch(BASE + '/feedback', { method: 'OPTIONS', headers: { origin: 'https://evil.workers.dev' } })).headers.get('access-control-allow-origin'), null);
  await settle();
  assert.equal(total(await stats(), 'lang', 'pv'), 0);
  assert.equal((await stats()).totals.length, before);
});

test('send to my Mac: counted on the phone, and the return visit on a Mac', async () => {
  execFileSync('npx', ['wrangler', 'd1', 'execute', 'notchfun', '--local', '--command', 'DELETE FROM counts;'], { stdio: 'ignore' });
  const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1';
  for (const c of ['open', 'share']) assert.equal((await post('/e', { e: 'send_mac', c, p: 'ios/phone' }, { 'user-agent': IPHONE })).status, 204);
  assert.equal((await post('/e', { e: 'send_mac', c: 'spam' }, { 'user-agent': IPHONE })).status, 400);
  // Later, on the Mac, from the shared link (?ref=sent).
  await post('/e', { b: [{ e: 'view', c: 'sent' }], p: 'mac/desktop' });
  // A phone opening the sent link doesn't count as coming back on a Mac.
  await post('/e', { b: [{ e: 'view', c: 'sent' }], p: 'ios/phone' }, { 'user-agent': IPHONE });
  await settle();
  const s = await stats();
  assert.equal(total(s, 'send_mac', 'open'), 1);
  assert.equal(total(s, 'send_mac', 'share'), 1);
  assert.equal(s.sentBackOnMac, 1);
});

test('email templates: HTML is escaped, plain text kept, sign-in link in both', async () => {
  const { feedbackEmail, signInEmail } = await import('../src/emails.js');
  const f = feedbackEmail({ id: 7, kind: 'bug', source: 'app', email: 'a@b.co', version: '1.6.1 (24)', macos: '26.1', message: '<img src=x onerror=alert(1)> & more\nline two', dashboard: 'https://d/admin' });
  assert.ok(!f.html.includes('<img src=x'), 'message markup is escaped');
  assert.ok(f.html.includes('&lt;img src=x onerror=alert(1)&gt; &amp; more'));
  assert.ok(f.html.includes('mailto:a@b.co'), 'Reply goes to the sender');
  assert.match(f.text, /From: a@b.co/);
  assert.equal(f.subject, 'Bug: <img src=x onerror=alert(1)> & more');
  const n = feedbackEmail({ id: 8, kind: 'idea', source: 'site', email: '', message: 'Hi', dashboard: 'https://d/admin' });
  assert.ok(!n.html.includes('mailto:'), 'no Reply button without an email');
  const si = signInEmail({ link: 'https://d/admin/login?t=abc', minutes: 15 });
  assert.ok(si.html.includes('https://d/admin/login?t=abc') && si.text.includes('https://d/admin/login?t=abc'));
});

test('funnel buttons: hero one-line install, after-download help, see how it works', async () => {
  for (const [e, c] of [['copy_curl', 'hero'], ['copy_curl', 'after_download'], ['dl_help', 'oneline'], ['dl_help', 'faq'], ['see_how', 'hero']]) {
    assert.equal((await post('/e', { e, c, p: 'mac/desktop' })).status, 204, `${e} ${c}`);
  }
  for (const bad of [{ e: 'dl_help', c: 'nope' }, { e: 'see_how', c: 'footer' }, { e: 'copy_curl', c: 'anywhere' }]) {
    assert.equal((await post('/e', bad)).status, 400);
  }
  await settle();
  const s = await stats();
  assert.equal(total(s, 'copy_curl', 'hero'), 1);
  assert.equal(total(s, 'dl_help', 'oneline'), 1);
  assert.equal(total(s, 'see_how', 'hero'), 1);
});

test('funnel: reaching either of the first two chapters counts as seeing the features', async () => {
  const ua = { 'user-agent': 'Shelf-first browser' };
  const before = (await stats()).funnel.features;
  await post('/e', { b: [{ e: 'view', c: '' }, { e: 'section', c: 'shelf' }] }, ua);
  await settle();
  assert.equal((await stats()).funnel.features - before, 1);
});

test('date ranges: exact windows for before/after, today never exceeded', async () => {
  execFileSync('npx', ['wrangler', 'd1', 'execute', 'notchfun', '--local', '--command',
    "DELETE FROM counts; INSERT INTO counts (day, event, channel, version, country, platform, n) VALUES " +
    "('2026-09-28','view','','','','mac/desktop',3), ('2026-09-29','view','','','','ios/phone',5), ('2026-10-01','view','','','','mac/desktop',7), " +
    "('2026-09-29','funnel','landed','','','mac/desktop',4), ('2026-09-29','funnel','install','','','mac/desktop',1);"], { stdio: 'ignore' });
  const get2 = q => get(`/stats?${q}`, { authorization: `Bearer ${ADMIN}` }).then(r => r.json());
  const a = await get2('from=2026-09-28&to=2026-09-29');
  assert.equal(a.days, 2); assert.equal(a.since, '2026-09-28'); assert.equal(a.until, '2026-09-29');
  assert.equal(total(a, 'view'), 8, 'only the two days');
  assert.deepEqual(a.funnel, { landed: 4, features: 0, install: 1, action: 0 }, 'no live journeys outside today');
  const mac = await get2('from=2026-09-28&to=2026-09-29&os=mac');
  assert.equal(total(mac, 'view'), 3);
  const b = await get2('from=2026-09-30&to=2099-01-01');
  assert.equal(total(b, 'view'), 7);
  assert.equal(b.until, new Date().toISOString().slice(0, 10), 'capped at today');
  const bad = await get2('from=yesterday');
  assert.equal(bad.days, 30, 'junk dates fall back to the last 30 days');
});

test('page speed: graded Core Web Vitals, nothing else', async () => {
  for (const [e, c] of [['lcp', 'good'], ['inp', 'ok'], ['cls', 'poor']]) assert.equal((await post('/e', { e, c })).status, 204);
  assert.equal((await post('/e', { e: 'lcp', c: '1234ms' })).status, 400);
  await settle();
  const s = await stats();
  assert.equal(total(s, 'lcp', 'good'), 1);
  assert.equal(total(s, 'cls', 'poor'), 1);
});
