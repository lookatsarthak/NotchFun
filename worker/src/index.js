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
const SITE_EVENTS = {
  view: null, // channel is the referring domain
  install_seen: new Set(['']),
  copy_curl: new Set(['', 'install']),
  copy_brew: new Set(['', 'install']),
  star_click: new Set(['hero', 'menubar', 'community', 'footer']),
  feedback_open: new Set(['idea', 'bug', 'other']),
};
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
      if (request.method === 'POST' && first === 'e') return siteEvent(request, env, ctx, cors);
      if (request.method === 'POST' && first === 'feedback') return feedback(request, env, ctx, cors);
      if (request.method === 'GET' && first === 'stats') return stats(request, env, url);
      if (request.method === 'GET' && first === 'admin') return new Response(ADMIN_HTML, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
      if (request.method === 'GET' && first === '') return new Response('NotchFun API\n', { headers: { 'content-type': 'text/plain' } });
      return new Response('Not found\n', { status: 404 });
    } catch (err) {
      console.error(err);
      return json({ error: 'server' }, 500, cors);
    }
  },

  async scheduled(event, env, ctx) {
    ctx.waitUntil(snapshot(env));
  },
};

// ------------------------------------------------------------------ downloads and installs

// The website's download buttons come through here so every click is counted, even with an
// ad blocker. The redirect never waits on the database: counting happens after it's sent.
function download(request, env, ctx, channel, url) {
  if (request.method === 'GET' && url.searchParams.get('nt') !== '1') {
    ctx.waitUntil(count(env, { event: 'dmg', channel: DMG_CHANNELS.has(channel) ? channel : 'other', country: country(request) }).catch(console.error));
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
async function siteEvent(request, env, ctx, cors) {
  if (!cors['access-control-allow-origin'] || BOT.test(request.headers.get('user-agent') ?? '')) return new Response(null, { status: 204, headers: cors });
  let body;
  try { body = JSON.parse((await request.text()).slice(0, 2000)); } catch { return new Response(null, { status: 400, headers: cors }); }
  const event = body?.e;
  if (!(event in SITE_EVENTS)) return new Response(null, { status: 400, headers: cors });
  let channel = typeof body.c === 'string' ? body.c.toLowerCase() : '';
  if (event === 'view') channel = DOMAIN.test(channel) ? channel.replace(/^www\./, '') : '';
  else if (!SITE_EVENTS[event].has(channel)) return new Response(null, { status: 400, headers: cors });

  ctx.waitUntil((async () => {
    await count(env, { event, channel, country: country(request) });
    if (event === 'view') {
      const hash = await visitorHash(env, request);
      const res = await env.DB.prepare('INSERT OR IGNORE INTO visitors (day, hash) VALUES (?1, ?2)').bind(today(), hash).run();
      if (res.meta.changes === 1) await count(env, { event: 'visitor', country: country(request) });
    }
  })().catch(console.error));
  return new Response(null, { status: 204, headers: cors });
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
  if (n > 5) return json({ error: 'rate' }, 429, cors);

  const { id } = await env.DB.prepare(
    `INSERT INTO feedback (created_at, kind, message, email, app_version, macos, source)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) RETURNING id`,
  ).bind(new Date().toISOString(), kind, message, email || null, version, macos, source).first();

  ctx.waitUntil(sendEmail(env, { id, kind, message, email, version, macos, source })
    .then(sent => sent && env.DB.prepare('UPDATE feedback SET emailed = 1 WHERE id = ?1').bind(id).run())
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
  if (!env.RESEND_API_KEY || !env.FEEDBACK_TO) return false;
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
  if (!res.ok) console.error('resend', res.status, await res.text());
  return res.ok;
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
  if (env.GITHUB_TOKEN) headers.authorization = `Bearer ${env.GITHUB_TOKEN}`;
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

  if (env.GITHUB_TOKEN) {
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
  return rows.length;
}

// ------------------------------------------------------------------ stats for the maintainer

async function stats(request, env, url) {
  if (!(await authorised(request, env))) return json({ error: 'unauthorised' }, 401);
  if (url.searchParams.get('snapshot') === '1') return json({ rows: await snapshot(env) });
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
  return json({ since, days, totals, daily, countries, versions, feedback: feedbackRows, github: latest, githubDaily: stars });
}

async function authorised(request, env) {
  if (!env.ADMIN_TOKEN) return false;
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(request.headers.get('authorization') ?? '')),
    crypto.subtle.digest('SHA-256', enc.encode(`Bearer ${env.ADMIN_TOKEN}`)),
  ]);
  return crypto.subtle.timingSafeEqual(a, b);
}

// ------------------------------------------------------------------ plumbing

function corsHeaders(request) {
  const origin = request.headers.get('origin');
  if (!origin || !ORIGINS.has(origin)) return {};
  return {
    'access-control-allow-origin': origin,
    'access-control-allow-methods': 'POST, OPTIONS',
    'access-control-allow-headers': 'content-type',
    'access-control-max-age': '86400',
    vary: 'origin',
  };
}

const json = (data, status = 200, headers = {}) =>
  new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store', ...headers } });

const redirect = location => new Response(null, { status: 302, headers: { location, 'cache-control': 'no-store' } });

