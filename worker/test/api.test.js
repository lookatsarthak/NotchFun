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
    'DELETE FROM counts; DELETE FROM visitors; DELETE FROM salts; DELETE FROM feedback; DELETE FROM limits; DELETE FROM snapshots;'], { stdio: 'ignore' });
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

test('feedback is limited to 5 an hour from one visitor', async () => {
  const body = { kind: 'idea', message: 'Rate limit check', token: 't' };
  const headers = { 'user-agent': 'Rate limit browser' };
  const codes = [];
  for (let i = 0; i < 7; i++) codes.push((await post('/feedback', body, headers)).status);
  assert.deepEqual(codes, [200, 200, 200, 200, 200, 429, 429]);
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
  const { rows } = await res.json();
  assert.ok(rows > 3, `copied ${rows} rows from GitHub`);
  const s = await stats();
  assert.ok(s.github.some(r => r.metric === 'stars'));
  assert.ok(s.github.some(r => r.metric.startsWith('asset:v1.6.1/')));
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
