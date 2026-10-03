// NotchFun's backend, a Cloudflare Worker with a D1 database. It does three things:
//   1. takes feedback from the website and the app, and emails it to the maintainer;
//   2. counts downloads and installs per channel, anonymously;
//   3. once a day, copies GitHub's numbers (stars, traffic, download counts), since
//      GitHub forgets traffic after 14 days.
// The app itself never talks to this. Only the website, install.sh and Homebrew do.

import ADMIN_HTML from './admin.html';

const REPO = 'lookatsarthak/NotchFun';
const DMG_LATEST = `https://github.com/${REPO}/releases/latest/download/NotchFun.dmg`;
const dmgFor = version => `https://github.com/${REPO}/releases/download/v${version}/NotchFun-${version}.dmg`;

const ORIGINS = new Set(['https://lookatsarthak.github.io', 'http://127.0.0.1:8765', 'http://localhost:8765']);

// Everything that can be counted, and the channels each may carry. Anything else is dropped.
// A Set lists the allowed channels; a RegExp describes them.
const CHAPTERS = 'music|shelf|clip|cal|keys|little';
const SITE_EVENTS = {
  view: null, // channel is the referring domain
  install_seen: new Set(['']),
  copy_curl: new Set(['', 'install']),
  copy_brew: new Set(['', 'install']),
  star_click: new Set(['hero', 'menubar', 'community', 'footer']),
  feedback_open: new Set(['idea', 'bug', 'other']),
  // How visitors behave: how far down they get, what they try, who they are.
  section: new Set(['hero', 'music', 'shelf', 'clip', 'cal', 'keys', 'little', 'native', 'install', 'changelog', 'community', 'faq', 'footer']),
  toggle: new RegExp(`^(${CHAPTERS}):(try|real)$`),
  video_end: new RegExp(`^(${CHAPTERS})$`),
  demo: new Set(['music:play', 'music:next', 'music:prev', 'shelf:drag', 'clip:copy', 'clip:search', 'keys:press',
    'little:caffeine', 'little:charging', 'little:airpods', 'little:mirror', 'native:width']),
  faq_open: new Set(['free', 'warning', 'macs', 'permissions', 'privacy']),
  changelog_more: new Set(['']),
  outbound: new Set(['github', 'releases', 'issues', 'license', 'contributing', 'install_script', 'other']),
  time: new Set(['<10s', '10-30s', '30s-2m', '2-5m', '5m+']),
  device: /^(mac|ios|windows|android|linux|other)\/(phone|tablet|desktop)$/,
  lang: /^[a-z]{2,3}$/,
};
const allowed = (rule, channel) => (rule instanceof RegExp ? rule.test(channel) : rule.has(channel));

// Funnel steps, recorded per daily visitor hash.
const STEP = { landed: 1, features: 2, install: 4, action: 8 };
const stepFor = (event, channel) =>
  event === 'view' ? STEP.landed
  : event === 'section' && channel === 'music' ? STEP.features
  : (event === 'section' && channel === 'install') || event === 'install_seen' ? STEP.install
  : event === 'copy_curl' || event === 'copy_brew' || event === 'dmg' ? STEP.action
  : 0;
const DMG_CHANNELS = new Set(['hero', 'install', 'readme', 'other']);
const INSTALL_STEPS = { start: 'curl_start', ok: 'curl_ok', fail: 'curl_fail' };
const FAIL_REASONS = new Set(['old_macos', 'not_mac', 'download', 'mount', 'copy', 'open', 'other']);
const KINDS = new Set(['idea', 'bug', 'other']);

const VERSION = /^\d{1,3}\.\d{1,3}\.\d{1,3}$/;
const DOMAIN = /^[a-z0-9.-]{1,64}$/;
const BOT = /bot|crawl|spider|slurp|preview|headless|lighthouse|python|wget|go-http/i;

const today = () => new Date().toISOString().slice(0, 10);
const daysAgo = n => new Date(Date.now() - n * 864e5).toISOString().slice(0, 10);

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const cors = corsHeaders(request);
    try {
      if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });

      const [, first, second] = url.pathname.split('/');
      // HEAD gets the same redirect (link checkers, download managers) but isn't counted.
      const read = request.method === 'GET' || request.method === 'HEAD';
      if (read && first === 'd') return download(request, env, ctx, second, url);
      if (read && first === 'brew') return brew(request, env, ctx, second, url);
      if (request.method === 'GET' && first === 'i') return installPing(request, env, ctx, url);
      if (request.method === 'GET' && first === 'gh' && (second === 'repo' || second === 'releases')) return githubPublic(env, ctx, second, cors);
      if (request.method === 'POST' && first === 'e') return siteEvent(request, env, ctx, cors);
      if (request.method === 'POST' && first === 'feedback') return feedback(request, env, ctx, cors);
      if (request.method === 'GET' && first === 'stats') return stats(request, env, url);
      if (first === 'admin' && second === 'link' && request.method === 'POST') return adminLink(request, env, url);
      if (first === 'admin' && second === 'login') return adminLogin(request, env, url);
      if (first === 'admin' && second === 'logout' && request.method === 'POST') return adminLogout(request, env);
      if (request.method === 'GET' && first === 'admin') return new Response(ADMIN_HTML, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', 'x-frame-options': 'DENY' } });
      if (request.method === 'GET' && first === '') return new Response('NotchFun API\n', { headers: { 'content-type': 'text/plain' } });
      return new Response('Not found\n', { status: 404 });
    } catch (err) {
      console.error(err);
      return json({ error: 'server' }, 500, cors);
    }
  },

  async scheduled(event, env, ctx) {
    ctx.waitUntil(Promise.all([snapshot(env), rollup(env)]));
  },
};

// ------------------------------------------------------------------ downloads and installs

// The website's download buttons come through here so every click is counted, even with an
// ad blocker. The redirect never waits on the database: counting happens after it's sent.
function download(request, env, ctx, channel, url) {
  if (request.method === 'GET' && url.searchParams.get('nt') !== '1') {
    ctx.waitUntil(Promise.all([
      count(env, { event: 'dmg', channel: DMG_CHANNELS.has(channel) ? channel : 'other', country: country(request) }),
      journey(env, request, STEP.action),
    ]).catch(console.error));
  }
  return redirect(DMG_LATEST);
}

// Homebrew's cask downloads through here, so brew installs are counted exactly.
function brew(request, env, ctx, version, url) {
  if (!VERSION.test(version ?? '')) return new Response('Unknown version\n', { status: 404 });
  if (request.method === 'GET' && url.searchParams.get('nt') !== '1') ctx.waitUntil(count(env, { event: 'brew', version, country: country(request) }).catch(console.error));
  return redirect(dmgFor(version));
}

// install.sh reports start, success, or the step it failed at. No identifiers.
async function installPing(request, env, ctx, url) {
  const q = url.searchParams;
  const event = INSTALL_STEPS[q.get('s')];
  if (event) {
    const reason = q.get('r');
    const arch = q.get('a') === 'x86_64' ? 'x86_64' : q.get('a') === 'arm64' ? 'arm64' : '';
    const macos = /^\d{2}$/.test(q.get('m') ?? '') ? q.get('m') : '';
    const channel = event === 'curl_fail' ? (FAIL_REASONS.has(reason) ? reason : 'other') : [arch, macos].filter(Boolean).join('/');
    const version = VERSION.test(q.get('v') ?? '') ? q.get('v') : '';
    ctx.waitUntil(count(env, { event, channel, version, country: country(request) }).catch(console.error));
  }
  return new Response(null, { status: 204 });
}

// The website's own counts: page views (with the referring domain), unique visitors, and
// clicks on star, copy and feedback. Sent with sendBeacon as text, so there's no preflight.
// One event as {e, c}, or up to 12 as {b: [{e, c}, ...]}. Anything not in SITE_EVENTS is
// refused; in a batch, the whole batch is.
async function siteEvent(request, env, ctx, cors) {
  if (!cors['access-control-allow-origin'] || BOT.test(request.headers.get('user-agent') ?? '')) return new Response(null, { status: 204, headers: cors });
  let body;
  try { body = JSON.parse((await request.text()).slice(0, 4000)); } catch { return new Response(null, { status: 400, headers: cors }); }
  const list = Array.isArray(body?.b) ? body.b : [body];
  if (!list.length || list.length > 12) return new Response(null, { status: 400, headers: cors });
  const events = [];
  for (const item of list) {
    const event = item?.e;
    if (!Object.hasOwn(SITE_EVENTS, event)) return new Response(null, { status: 400, headers: cors });
    let channel = typeof item.c === 'string' ? item.c.toLowerCase() : '';
    if (event === 'view') channel = DOMAIN.test(channel) ? channel.replace(/^www\./, '') : '';
    else if (!allowed(SITE_EVENTS[event], channel)) return new Response(null, { status: 400, headers: cors });
    events.push({ event, channel });
  }

  ctx.waitUntil((async () => {
    const where = country(request);
    let steps = 0;
    for (const { event, channel } of events) {
      await count(env, { event, channel, country: where });
      steps |= stepFor(event, channel);
    }
    if (events.some(e => e.event === 'view')) {
      const hash = await visitorHash(env, request);
      const res = await env.DB.prepare('INSERT OR IGNORE INTO visitors (day, hash) VALUES (?1, ?2)').bind(today(), hash).run();
      if (res.meta.changes === 1) await count(env, { event: 'visitor', country: where });
    }
    if (steps) await journey(env, request, steps);
  })().catch(console.error));
  return new Response(null, { status: 204, headers: cors });
}

async function journey(env, request, steps) {
  const hash = await visitorHash(env, request);
  await env.DB.prepare(
    `INSERT INTO journeys (day, hash, steps) VALUES (?1, ?2, ?3)
     ON CONFLICT (day, hash) DO UPDATE SET steps = steps | ?3`,
  ).bind(today(), hash, steps).run();
}

// Folds finished days' journeys into funnel counts, then forgets them.
async function rollup(env) {
  const day = today();
  const stmts = Object.entries(STEP).map(([name, bit]) => env.DB.prepare(
    `INSERT INTO counts (day, event, channel, version, country, n)
     SELECT day, 'funnel', ?1, '', '', COUNT(*) FROM journeys WHERE day < ?2 AND steps & ?3 GROUP BY day
     ON CONFLICT (day, event, channel, version, country) DO UPDATE SET n = n + excluded.n`,
  ).bind(name, day, bit));
  await env.DB.batch([...stmts, env.DB.prepare('DELETE FROM journeys WHERE day < ?1').bind(day)]);
}

async function count(env, { event, channel = '', version = '', country = '' }) {
  await env.DB.prepare(
    `INSERT INTO counts (day, event, channel, version, country, n) VALUES (?1, ?2, ?3, ?4, ?5, 1)
     ON CONFLICT (day, event, channel, version, country) DO UPDATE SET n = n + 1`,
  ).bind(today(), event, channel, version, country).run();
}

// ------------------------------------------------------------------ feedback

async function feedback(request, env, ctx, cors) {
  if (!cors['access-control-allow-origin']) return json({ error: 'origin' }, 403, cors);
  let body;
  try { body = JSON.parse((await request.text()).slice(0, 20000)); } catch { return json({ error: 'bad_request' }, 400, cors); }
  // A field people can't see. Bots fill it in; they get a cheerful "ok" and nothing is kept.
  if (body.website) return json({ ok: true }, 200, cors);

  const kind = KINDS.has(body.kind) ? body.kind : 'other';
  const message = String(body.message ?? '').replace(/\r\n?/g, '\n').trim();
  if (message.length < 3 || message.length > 5000) return json({ error: 'message' }, 400, cors);
  const email = String(body.email ?? '').trim();
  if (email && (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))) return json({ error: 'email' }, 400, cors);
  const version = /^\d+\.\d+\.\d+( \(\d+\))?$/.test(body.version ?? '') ? body.version : null;
  const macos = /^(macOS )?\d+\.\d+(\.\d+)?$/.test(body.os ?? '') ? body.os.replace(/^macOS /, '') : null;
  const source = body.source === 'app' ? 'app' : 'site';

  if (!(await verifyTurnstile(env, body.token, request.headers.get('cf-connecting-ip')))) return json({ error: 'verify' }, 403, cors);

  const key = await visitorHash(env, request);
  const hour = new Date().toISOString().slice(0, 13);
  const { n } = await env.DB.prepare(
    `INSERT INTO limits (key, hour, n) VALUES (?1, ?2, 1)
     ON CONFLICT (key, hour) DO UPDATE SET n = n + 1 RETURNING n`,
  ).bind(key, hour).first();
  // Per network + browser, so people sharing one Wi-Fi share it; Turnstile is the real bot check.
  if (n > 20) return json({ error: 'rate' }, 429, cors);

  const { id } = await env.DB.prepare(
    `INSERT INTO feedback (created_at, kind, message, email, app_version, macos, source)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) RETURNING id`,
  ).bind(new Date().toISOString(), kind, message, email || null, version, macos, source).first();

  ctx.waitUntil(sendEmail(env, { id, kind, message, email, version, macos, source })
    .then(r => r.ok && env.DB.prepare('UPDATE feedback SET emailed = 1 WHERE id = ?1').bind(id).run())
    .catch(console.error));
  return json({ ok: true }, 200, cors);
}

async function verifyTurnstile(env, token, ip) {
  if (!env.TURNSTILE_SECRET || typeof token !== 'string' || !token) return false;
  const form = new FormData();
  form.append('secret', env.TURNSTILE_SECRET);
  form.append('response', token);
  if (ip) form.append('remoteip', ip);
  const res = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', { method: 'POST', body: form });
  return res.ok && (await res.json()).success === true;
}

// Sent with Resend to the maintainer's own address, which lives only in a Worker secret.
// Replying goes to the person, if they left an email.
async function sendEmail(env, f) {
  if (!env.RESEND_API_KEY || !env.FEEDBACK_TO) return { ok: false, status: 0, error: 'RESEND_API_KEY or FEEDBACK_TO not set' };
  const label = { idea: 'Idea', bug: 'Bug', other: 'Feedback' }[f.kind];
  const firstLine = f.message.split('\n')[0].slice(0, 70);
  const text = [
    f.message,
    '',
    '—',
    `From: ${f.email || 'no email given'}`,
    `Sent from: the ${f.source === 'app' ? 'app' : 'website'}`,
    f.version ? `NotchFun: ${f.version}` : null,
    f.macos ? `macOS: ${f.macos}` : null,
    `#${f.id}`,
  ].filter(v => v !== null).join('\n');
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      from: 'NotchFun feedback <onboarding@resend.dev>',
      to: [env.FEEDBACK_TO],
      ...(f.email ? { reply_to: f.email } : {}),
      subject: `${label}: ${firstLine}`,
      text,
    }),
  });
  if (res.ok) return { ok: true, status: res.status };
  const error = (await res.text()).slice(0, 300);
  console.error('resend', res.status, error);
  return { ok: false, status: res.status, error };
}

// Retries feedback whose email failed, and says why if it fails again.
async function resendUnsent(env) {
  const rows = (await env.DB.prepare('SELECT * FROM feedback WHERE emailed = 0 ORDER BY id').all()).results;
  const results = [];
  for (const row of rows) {
    const r = await sendEmail(env, { id: row.id, kind: row.kind, message: row.message, email: row.email ?? '', version: row.app_version, macos: row.macos, source: row.source });
    if (r.ok) await env.DB.prepare('UPDATE feedback SET emailed = 1 WHERE id = ?1').bind(row.id).run();
    results.push({ id: row.id, ...r });
  }
  return results;
}

// ------------------------------------------------------------------ privacy helpers

// A hash of IP and browser with today's random salt. Yesterday's salt is deleted each
// night, so the hash can't be tied to anything after the day is over.
async function visitorHash(env, request) {
  const day = today();
  await env.DB.prepare('INSERT OR IGNORE INTO salts (day, salt) VALUES (?1, ?2)').bind(day, crypto.randomUUID()).run();
  const { salt } = await env.DB.prepare('SELECT salt FROM salts WHERE day = ?1').bind(day).first();
  const input = `${salt}|${request.headers.get('cf-connecting-ip') ?? ''}|${request.headers.get('user-agent') ?? ''}`;
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return [...new Uint8Array(digest)].slice(0, 16).map(b => b.toString(16).padStart(2, '0')).join('');
}

const country = request => (/^[A-Z]{2}$/.test(request.cf?.country ?? '') ? request.cf.country : '');

// ------------------------------------------------------------------ daily GitHub copy

async function snapshot(env) {
  const day = today();
  const headers = { 'user-agent': 'notchfun-api', accept: 'application/vnd.github+json' };
  const { token, via } = await githubToken(env);
  if (token) headers.authorization = `Bearer ${token}`;
  const gh = async path => {
    const r = await fetch(`https://api.github.com/repos/${REPO}${path}`, { headers });
    if (r.ok) return r.json();
    console.error('github', path, r.status, (await r.text()).slice(0, 200));
    return null;
  };
  const rows = []; // [day, metric, value]

  const repo = await gh('');
  if (repo) rows.push([day, 'stars', repo.stargazers_count], [day, 'forks', repo.forks_count], [day, 'watchers', repo.subscribers_count]);

  const releases = await gh('/releases?per_page=100');
  if (releases) {
    let latestName = 0, versioned = 0;
    for (const r of releases) for (const a of r.assets) {
      rows.push([day, `asset:${r.tag_name}/${a.name}`, a.download_count]);
      if (a.name === 'NotchFun.dmg') latestName += a.download_count; else versioned += a.download_count;
    }
    rows.push([day, 'gh_downloads_notchfun_dmg', latestName], [day, 'gh_downloads_versioned', versioned]);
  }

  if (token) {
    const views = await gh('/traffic/views?per=day');
    for (const v of views?.views ?? []) rows.push([v.timestamp.slice(0, 10), 'gh_views', v.count], [v.timestamp.slice(0, 10), 'gh_view_uniques', v.uniques]);
    const clones = await gh('/traffic/clones?per=day');
    for (const c of clones?.clones ?? []) rows.push([c.timestamp.slice(0, 10), 'gh_clones', c.count], [c.timestamp.slice(0, 10), 'gh_clone_uniques', c.uniques]);
    const refs = await gh('/traffic/popular/referrers');
    for (const r of refs ?? []) rows.push([day, `gh_ref14:${r.referrer}`, r.count]);
  }

  const upsert = env.DB.prepare('INSERT INTO snapshots (day, metric, value) VALUES (?1, ?2, ?3) ON CONFLICT (day, metric) DO UPDATE SET value = excluded.value');
  await env.DB.batch([
    ...rows.map(r => upsert.bind(...r)),
    env.DB.prepare('DELETE FROM visitors WHERE day < ?1').bind(day),
    env.DB.prepare('DELETE FROM salts WHERE day < ?1').bind(day),
    env.DB.prepare('DELETE FROM limits WHERE hour < ?1').bind(new Date(Date.now() - 864e5).toISOString().slice(0, 13)),
  ]);
  return { rows: rows.length, via };
}

// GitHub access through the NotchFun Stats GitHub App: a JWT signed with the app's key buys a
// one-hour token for its single installation (NotchFun, read-only). Nothing expires on our
// side. A personal token in GITHUB_TOKEN still works as a fallback.
async function githubToken(env) {
  if (env.GITHUB_APP_KEY && env.GITHUB_APP_ID && env.GITHUB_APP_INSTALLATION) {
    try {
      const b64url = bytes => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
      const part = obj => b64url(new TextEncoder().encode(JSON.stringify(obj)));
      const now = Math.floor(Date.now() / 1000);
      const unsigned = `${part({ alg: 'RS256', typ: 'JWT' })}.${part({ iat: now - 60, exp: now + 540, iss: String(env.GITHUB_APP_ID) })}`;
      const der = Uint8Array.from(atob(env.GITHUB_APP_KEY.replace(/-----[^-]+-----|\s/g, '')), c => c.charCodeAt(0));
      const key = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
      const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned));
      const res = await fetch(`https://api.github.com/app/installations/${env.GITHUB_APP_INSTALLATION}/access_tokens`, {
        method: 'POST',
        headers: { authorization: `Bearer ${unsigned}.${b64url(signature)}`, accept: 'application/vnd.github+json', 'user-agent': 'notchfun-api' },
      });
      if (res.ok) return { token: (await res.json()).token, via: 'app' };
      console.error('github app', res.status, (await res.text()).slice(0, 200));
    } catch (err) {
      console.error('github app', err);
    }
  }
  return env.GITHUB_TOKEN ? { token: env.GITHUB_TOKEN, via: 'token' } : { token: null, via: 'none' };
}

// The website's changelog and star count, fetched once every 10 minutes for everyone
// instead of by each visitor. GitHub allows only 60 anonymous calls an hour per network,
// which a group visiting from one office would use up in minutes.
async function githubPublic(env, ctx, which, cors) {
  const cache = caches.default;
  const key = new Request(`https://cache.notchfun/gh/${which}`);
  const hit = await cache.match(key);
  if (hit) return withHeaders(hit, cors);
  const { token } = await githubToken(env);
  const res = await fetch(`https://api.github.com/repos/${REPO}${which === 'repo' ? '' : '/releases?per_page=6'}`, {
    headers: { 'user-agent': 'notchfun-api', accept: 'application/vnd.github+json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
  });
  if (!res.ok) return json({ error: 'github', status: res.status }, 502, cors);
  const data = await res.json();
  const slim = which === 'repo'
    ? { stargazers_count: data.stargazers_count, forks_count: data.forks_count }
    : data.map(r => ({
        tag_name: r.tag_name, name: r.name, body: r.body, draft: r.draft, prerelease: r.prerelease,
        published_at: r.published_at, created_at: r.created_at, html_url: r.html_url,
        assets: r.assets.map(a => ({ name: a.name, size: a.size, browser_download_url: a.browser_download_url })),
      }));
  const out = new Response(JSON.stringify(slim), { headers: { 'content-type': 'application/json', 'cache-control': 'public, max-age=600' } });
  ctx.waitUntil(cache.put(key, out.clone()));
  return withHeaders(out, cors);
}

function withHeaders(res, headers) {
  const out = new Response(res.body, res);
  for (const [k, v] of Object.entries(headers)) out.headers.set(k, v);
  return out;
}

// ------------------------------------------------------------------ stats for the maintainer

async function stats(request, env, url) {
  if (!(await authorised(request, env))) return json({ error: 'unauthorised' }, 401);
  if (url.searchParams.get('snapshot') === '1') { await rollup(env); return json(await snapshot(env)); }
  if (url.searchParams.get('resend') === '1') return json({ resent: await resendUnsent(env) });
  const days = Math.min(365, Math.max(1, parseInt(url.searchParams.get('days') ?? '30', 10) || 30));
  const since = daysAgo(days - 1);
  const all = (sql, ...args) => env.DB.prepare(sql).bind(...args).all().then(r => r.results);
  const [totals, daily, countries, versions, feedbackRows, latest, stars] = await Promise.all([
    all('SELECT event, channel, SUM(n) AS n FROM counts WHERE day >= ?1 GROUP BY event, channel ORDER BY event, n DESC', since),
    all('SELECT day, event, SUM(n) AS n FROM counts WHERE day >= ?1 GROUP BY day, event ORDER BY day', since),
    all(`SELECT country, SUM(n) AS n FROM counts WHERE day >= ?1 AND event IN ('dmg', 'brew', 'curl_ok') GROUP BY country ORDER BY n DESC LIMIT 20`, since),
    all(`SELECT event, version, SUM(n) AS n FROM counts WHERE day >= ?1 AND version != '' GROUP BY event, version ORDER BY version DESC`, since),
    all('SELECT * FROM feedback ORDER BY id DESC LIMIT 100'),
    all('SELECT metric, value FROM snapshots WHERE day = (SELECT MAX(day) FROM snapshots WHERE metric = ?1)', 'stars'),
    all(`SELECT day, metric, value FROM snapshots WHERE day >= ?1 AND metric IN ('stars', 'gh_views', 'gh_view_uniques', 'gh_clones') ORDER BY day`, since),
  ]);
  const live = await env.DB.prepare(
    `SELECT SUM(steps & 1 > 0) AS landed, SUM(steps & 2 > 0) AS features, SUM(steps & 4 > 0) AS install, SUM(steps & 8 > 0) AS action
     FROM journeys WHERE day = ?1`,
  ).bind(today()).first();
  const funnel = Object.fromEntries(Object.keys(STEP).map(name => [name,
    totals.filter(t => t.event === 'funnel' && t.channel === name).reduce((a, t) => a + t.n, 0) + (live?.[name] ?? 0)]));
  return json({ since, days, totals, daily, countries, versions, funnel, feedback: feedbackRows, github: latest, githubDaily: stars });
}

async function authorised(request, env) {
  const session = cookie(request, SESSION_COOKIE);
  if (session) {
    const row = await env.DB.prepare('SELECT expires FROM admin_sessions WHERE hash = ?1').bind(await sha256(session)).first();
    if (row && row.expires > Date.now()) return true;
  }
  if (!env.ADMIN_TOKEN) return false;
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(request.headers.get('authorization') ?? '')),
    crypto.subtle.digest('SHA-256', enc.encode(`Bearer ${env.ADMIN_TOKEN}`)),
  ]);
  return crypto.subtle.timingSafeEqual(a, b);
}

// ------------------------------------------------------------------ maintainer sign-in

// No password: the dashboard emails a one-use link to FEEDBACK_TO (the maintainer's own
// inbox), and following it starts a 90-day session in that browser. The link opens a page
// with a button rather than signing in on GET, so mail scanners that open links can't use
// it up.
const SESSION_COOKIE = '__Host-nf_admin';
const LINK_MINUTES = 15;
const SESSION_DAYS = 90;

async function adminLink(request, env, url) {
  if (request.headers.get('origin') !== url.origin) return json({ error: 'origin' }, 403);
  const hour = new Date().toISOString().slice(0, 13);
  const { n } = await env.DB.prepare(
    `INSERT INTO limits (key, hour, n) VALUES ('admin-link', ?1, 1)
     ON CONFLICT (key, hour) DO UPDATE SET n = n + 1 RETURNING n`,
  ).bind(hour).first();
  if (n > 3) return json({ error: 'rate' }, 429);
  const token = randomToken();
  await env.DB.prepare('INSERT INTO admin_links (hash, expires) VALUES (?1, ?2)').bind(await sha256(token), Date.now() + LINK_MINUTES * 60e3).run();
  const link = `${url.origin}/admin/login?t=${token}`;
  if (env.DEV === '1') return json({ ok: true, link }); // local tests only; never set in production
  if (!env.RESEND_API_KEY || !env.FEEDBACK_TO) return json({ error: 'email' }, 500);
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      from: 'NotchFun numbers <onboarding@resend.dev>',
      to: [env.FEEDBACK_TO],
      subject: 'Your NotchFun dashboard sign-in link',
      text: `Open this to sign in to the NotchFun dashboard on the device you asked from:\n\n${link}\n\nIt works once, for ${LINK_MINUTES} minutes. If you didn't ask for it, ignore this email.`,
    }),
  });
  return res.ok ? json({ ok: true }) : json({ error: 'email' }, 502);
}

async function adminLogin(request, env, url) {
  const page = (body, status = 200) => new Response(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex"><title>NotchFun numbers</title>
<style>body{margin:0;min-height:100svh;display:grid;place-items:center;background:#0b0a1c;color:#f3f1ff;font:16px/1.5 -apple-system,system-ui,sans-serif;text-align:center;padding:24px}
button,a{font:inherit;font-weight:600;border:0;border-radius:999px;padding:12px 24px;background:#b9a4ff;color:#120f2a;cursor:pointer;text-decoration:none;display:inline-block}p{color:#a9a4c9}</style>${body}`,
    { status, headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', 'x-frame-options': 'DENY', 'referrer-policy': 'no-referrer' } });

  if (request.method === 'GET') {
    const t = url.searchParams.get('t') ?? '';
    if (!/^[A-Za-z0-9_-]{43}$/.test(t)) return page('<main><h1>That link is broken.</h1><p>Ask for a new one from the dashboard.</p><a href="/admin">Open the dashboard</a></main>', 400);
    return page(`<main><h1>Sign in to NotchFun numbers</h1><p>This browser stays signed in for ${SESSION_DAYS} days.</p><form method="post"><input type="hidden" name="t" value="${t}"><button>Sign in</button></form></main>`);
  }
  if (request.method !== 'POST') return new Response('Method not allowed\n', { status: 405 });
  const t = String((await request.formData()).get('t') ?? '');
  const hash = await sha256(t);
  const row = await env.DB.prepare('UPDATE admin_links SET used = 1 WHERE hash = ?1 AND used = 0 AND expires > ?2 RETURNING hash').bind(hash, Date.now()).first();
  if (!row) return page('<main><h1>That link has expired or was already used.</h1><p>Ask for a new one; it takes a few seconds.</p><a href="/admin">Open the dashboard</a></main>', 400);
  const session = randomToken();
  await env.DB.batch([
    env.DB.prepare('INSERT INTO admin_sessions (hash, expires) VALUES (?1, ?2)').bind(await sha256(session), Date.now() + SESSION_DAYS * 864e5),
    env.DB.prepare('DELETE FROM admin_sessions WHERE expires < ?1').bind(Date.now()),
    env.DB.prepare('DELETE FROM admin_links WHERE expires < ?1').bind(Date.now()),
  ]);
  return new Response(null, { status: 303, headers: {
    location: '/admin',
    'set-cookie': `${SESSION_COOKIE}=${session}; Path=/; Max-Age=${SESSION_DAYS * 86400}; HttpOnly; Secure; SameSite=Strict`,
    'cache-control': 'no-store',
  } });
}

async function adminLogout(request, env) {
  const session = cookie(request, SESSION_COOKIE);
  if (session) await env.DB.prepare('DELETE FROM admin_sessions WHERE hash = ?1').bind(await sha256(session)).run();
  return new Response(null, { status: 204, headers: { 'set-cookie': `${SESSION_COOKIE}=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Strict` } });
}

function cookie(request, name) {
  const match = (request.headers.get('cookie') ?? '').split(/;\s*/).find(c => c.startsWith(`${name}=`));
  return match ? match.slice(name.length + 1) : null;
}

function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}

async function sha256(text) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
}

// ------------------------------------------------------------------ plumbing

function corsHeaders(request) {
  const origin = request.headers.get('origin');
  if (!origin || !ORIGINS.has(origin)) return {};
  return {
    'access-control-allow-origin': origin,
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers': 'content-type',
    'access-control-max-age': '86400',
    vary: 'origin',
  };
}

const json = (data, status = 200, headers = {}) =>
  new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store', ...headers } });

const redirect = location => new Response(null, { status: 302, headers: { location, 'cache-control': 'no-store' } });

