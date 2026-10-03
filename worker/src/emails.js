// The emails the backend sends, both to the maintainer: new feedback, and a dashboard
// sign-in link. Each has an HTML version in the site's look (night sky, lavender, a black
// notch at the top) and a plain-text one for mail apps that prefer it. Tables and inline
// styles only, because that's what Gmail, Apple Mail and Outlook all render the same.

const SITE = 'https://lookatsarthak.github.io/NotchFun/';
const ICON = 'https://lookatsarthak.github.io/NotchFun/assets/icon.png';
const C = { night: '#0b0a1c', card: '#16142e', line: '#2a2650', ink: '#f4f2ff', ink2: '#b4aed6', ink3: '#857fa8', lav: '#b9a8ff', pink: '#ff8fb8', bug: '#ff7ab8' };
const FONT = "-apple-system, BlinkMacSystemFont, 'SF Pro Rounded', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif";

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function layout({ pill, preheader, body }) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark light"><meta name="supported-color-schemes" content="dark light"><title>NotchFun</title></head>
<body style="margin:0;padding:0;background:${C.night};">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:${C.night};">${esc(preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${C.night};background-image:linear-gradient(180deg,#07071a 0%,#14103a 60%,#231a55 100%);">
  <tr><td align="center" style="padding:0 12px 40px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">
      <tr><td align="center" style="padding:0 0 28px;">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="background:#000;border-radius:0 0 16px 16px;">
          <tr><td style="padding:9px 18px 10px;font:600 13px ${FONT};color:rgba(255,255,255,0.8);white-space:nowrap;">
            <img src="${ICON}" width="16" height="16" alt="" style="vertical-align:-3px;border:0;border-radius:4px;margin-right:7px;">${esc(pill)}
          </td></tr>
        </table>
      </td></tr>
      ${body}
      <tr><td align="center" style="padding:26px 8px 0;font:400 12px/1.6 ${FONT};color:${C.ink3};">
        <a href="${SITE}" style="color:${C.ink3};text-decoration:none;"><strong style="color:${C.ink2};">NotchFun</strong> · the notch, but fun.</a>
      </td></tr>
    </table>
  </td></tr>
</table>
</body></html>`;
}

const card = inner => `<tr><td style="background:${C.card};border:1px solid ${C.line};border-radius:20px;padding:26px 26px 24px;">${inner}</td></tr>`;

const button = (href, text, primary = true) =>
  `<a href="${esc(href)}" style="display:inline-block;padding:13px 26px;border-radius:999px;font:700 15px ${FONT};text-decoration:none;${
    primary ? `background:#ffffff;color:#0b0920;` : `background:transparent;color:${C.ink};border:1px solid ${C.line};`}">${esc(text)}</a>`;

// ------------------------------------------------------------------ feedback

export function feedbackEmail(f) {
  const kind = { idea: 'Idea', bug: 'Bug report', other: 'Feedback' }[f.kind] ?? 'Feedback';
  const firstLine = f.message.split('\n')[0].slice(0, 70);
  const subject = `${{ idea: 'Idea', bug: 'Bug', other: 'Feedback' }[f.kind] ?? 'Feedback'}: ${firstLine}`;
  const when = new Date().toUTCString().replace(' GMT', ' UTC');
  const rows = [
    ['From', f.email ? `<a href="mailto:${esc(f.email)}" style="color:${C.lav};text-decoration:none;">${esc(f.email)}</a>` : 'No email given'],
    ['Sent from', f.source === 'app' ? 'The app' : 'The website'],
    f.version ? ['NotchFun', esc(f.version)] : null,
    f.macos ? ['macOS', esc(f.macos)] : null,
    ['Received', esc(when)],
  ].filter(Boolean);

  const html = layout({
    pill: kind,
    preheader: firstLine,
    body: card(`
      <p style="margin:0 0 6px;font:700 12px ${FONT};letter-spacing:0.08em;text-transform:uppercase;color:${f.kind === 'bug' ? C.bug : C.lav};">${esc(kind)} · #${f.id}</p>
      <div style="margin:0 0 22px;font:400 17px/1.6 ${FONT};color:${C.ink};white-space:pre-wrap;word-break:break-word;">${esc(f.message)}</div>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-top:1px solid ${C.line};">
        ${rows.map(([k, v]) => `<tr><td style="padding:10px 12px 0 0;font:500 13px ${FONT};color:${C.ink3};white-space:nowrap;vertical-align:top;width:90px;">${k}</td><td style="padding:10px 0 0;font:500 14px ${FONT};color:${C.ink2};">${v}</td></tr>`).join('')}
      </table>
      <div style="padding-top:24px;">
        ${f.email ? `${button(`mailto:${f.email}?subject=${encodeURIComponent(`Re: ${subject}`)}`, 'Reply')}&nbsp;&nbsp;` : ''}${button(`${f.dashboard}`, 'Open dashboard', !f.email)}
      </div>`),
  });

  const text = [
    f.message, '', '—',
    `From: ${f.email || 'no email given'}`,
    `Sent from: the ${f.source === 'app' ? 'app' : 'website'}`,
    f.version ? `NotchFun: ${f.version}` : null,
    f.macos ? `macOS: ${f.macos}` : null,
    `#${f.id}`,
    '', `Dashboard: ${f.dashboard}`,
  ].filter(v => v !== null).join('\n');

  return { subject, html, text };
}

// ------------------------------------------------------------------ sign-in

export function signInEmail({ link, minutes }) {
  const html = layout({
    pill: 'Sign in',
    preheader: `Your sign-in link for the NotchFun dashboard. It works once, for ${minutes} minutes.`,
    body: card(`
      <h1 style="margin:0 0 10px;font:800 26px/1.2 ${FONT};letter-spacing:-0.02em;color:${C.ink};">Sign in to NotchFun numbers</h1>
      <p style="margin:0 0 24px;font:400 16px/1.6 ${FONT};color:${C.ink2};">Open this on the device you want to use. It stays signed in for 90 days.</p>
      <div>${button(link, 'Sign in')}</div>
      <p style="margin:24px 0 0;font:400 13px/1.6 ${FONT};color:${C.ink3};">The link works once, for ${minutes} minutes. If you didn't ask for it, ignore this email — nothing happens without it.</p>`),
  });
  const text = `Open this to sign in to the NotchFun dashboard on the device you asked from:\n\n${link}\n\nIt works once, for ${minutes} minutes. If you didn't ask for it, ignore this email.`;
  return { subject: 'Your NotchFun dashboard sign-in link', html, text };
}
