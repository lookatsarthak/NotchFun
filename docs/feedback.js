// The feedback form, used in a dialog on the home page and on its own at feedback.html
// (which the app opens, with its version and macOS filled in). No GitHub account needed:
// it goes to the backend, which emails it to the maintainer.

import { API, TURNSTILE_SITEKEY, track } from './api.js';

const PROMPTS = {
  idea: 'What should the notch do?',
  bug: 'What happened, and what did you expect instead?',
  other: "What's on your mind?",
};
const ERRORS = {
  message: 'Write a little more — at least a few words.',
  email: "That email doesn't look right. Leave it empty if you don't want a reply.",
  verify: "We couldn't check you're not a bot. Try again in a moment.",
  rate: "That's a lot of messages in an hour. Try again a bit later.",
  network: "Couldn't send. Check your connection and try again.",
};

// Cloudflare Turnstile, loaded only once someone opens a form. Set to show nothing unless
// Cloudflare needs the visitor to click.
let turnstileReady;
function loadTurnstile() {
  turnstileReady ??= new Promise((resolve, reject) => {
    window.__nfTurnstile = () => resolve(window.turnstile);
    const s = document.createElement('script');
    s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit&onload=__nfTurnstile';
    s.async = true;
    s.onerror = reject;
    document.head.append(s);
  });
  return turnstileReady;
}

/**
 * Builds the form inside `root`.
 * @param {{ kind?: string, version?: string, os?: string, source?: 'site' | 'app', onSent?: () => void }} options
 * @returns {{ setKind(kind: string): void, focus(): void, reset(): void }}
 */
export function feedbackForm(root, { kind = 'idea', version = '', os = '', source = 'site', onSent } = {}) {
  root.innerHTML = `
    <form class="fb-form" novalidate>
      <div class="fb-kinds" role="radiogroup" aria-label="What is it?">
        ${[['idea', 'Idea'], ['bug', 'Bug'], ['other', 'Something else']].map(([value, label]) => `
          <label class="fb-kind"><input type="radio" name="kind" value="${value}"><span>${label}</span></label>`).join('')}
      </div>
      <label class="fb-field">
        <span class="fb-label">Message</span>
        <textarea name="message" rows="6" maxlength="5000" required></textarea>
      </label>
      <label class="fb-field">
        <span class="fb-label">Email <small>optional, only for a reply</small></span>
        <input name="email" type="email" autocomplete="email" inputmode="email" spellcheck="false">
      </label>
      <label class="fb-trap" aria-hidden="true">Website <input name="website" tabindex="-1" autocomplete="off"></label>
      ${version || os ? `<p class="fb-context">Sent with ${[version && `NotchFun ${version}`, os && `macOS ${os.replace(/^macOS /, '')}`].filter(Boolean).join(' · ')}</p>` : ''}
      <div class="fb-turnstile"></div>
      <p class="fb-error" role="alert" hidden></p>
      <div class="fb-actions">
        <button class="fb-send" type="submit"><span>Send</span></button>
        <a class="fb-gh" href="https://github.com/lookatsarthak/NotchFun/issues/new/choose" target="_blank" rel="noopener">Prefer GitHub? Open an issue</a>
      </div>
    </form>
    <div class="fb-done" hidden>
      <svg viewBox="0 0 52 52" aria-hidden="true"><circle cx="26" cy="26" r="24"/><path d="M15 27l7 7 15-16"/></svg>
      <h3>Thanks — it's on its way.</h3>
      <p class="fb-done-note"></p>
      <button class="fb-again" type="button">Send another</button>
    </div>`;

  const form = root.querySelector('form');
  const message = form.elements.message;
  const errorEl = root.querySelector('.fb-error');
  const send = root.querySelector('.fb-send');
  const done = root.querySelector('.fb-done');

  // Turnstile hands over a one-use token; a submit waits for it if it isn't here yet.
  let widget = null, token = null, waiting = [];
  const turnstile = loadTurnstile().then(ts => {
    widget = ts.render(root.querySelector('.fb-turnstile'), {
      sitekey: TURNSTILE_SITEKEY,
      appearance: 'interaction-only',
      theme: 'dark',
      action: 'feedback',
      callback: t => { token = t; waiting.splice(0).forEach(fn => fn(t)); },
      'expired-callback': () => { token = null; },
      'error-callback': () => { token = null; },
    });
    return ts;
  }).catch(() => null);
  const getToken = () => token ? Promise.resolve(token) : new Promise((resolve, reject) => {
    waiting.push(resolve);
    setTimeout(() => reject(new Error('verify')), 20000);
  });

  const setKind = value => {
    const k = PROMPTS[value] ? value : 'idea';
    form.elements.kind.value = k;
    message.placeholder = PROMPTS[k];
  };
  form.addEventListener('change', e => { if (e.target.name === 'kind') setKind(e.target.value); });
  setKind(kind);

  const showError = key => { errorEl.textContent = ERRORS[key] ?? ERRORS.network; errorEl.hidden = false; };

  form.addEventListener('submit', async e => {
    e.preventDefault();
    errorEl.hidden = true;
    const text = message.value.trim();
    const email = form.elements.email.value.trim();
    if (text.length < 3) { showError('message'); message.focus(); return; }
    if (email && !form.elements.email.checkValidity()) { showError('email'); form.elements.email.focus(); return; }

    send.disabled = true;
    send.firstElementChild.textContent = 'Sending…';
    try {
      const res = await fetch(`${API}/feedback`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          kind: form.elements.kind.value, message: text, email, version, os, source,
          website: form.elements.website.value, token: await getToken(),
        }),
      });
      if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error ?? 'network');
      form.hidden = true;
      done.querySelector('.fb-done-note').textContent = email ? `If there's something to reply to, the answer goes to ${email}.` : 'You can send another any time.';
      done.hidden = false;
      onSent?.();
    } catch (err) {
      showError(err.message);
    } finally {
      send.disabled = false;
      send.firstElementChild.textContent = 'Send';
      token = null;
      turnstile.then(ts => ts && widget !== null && ts.reset(widget));
    }
  });

  const reset = () => {
    form.reset();
    setKind(form.elements.kind.value || kind);
    errorEl.hidden = true;
    form.hidden = false;
    done.hidden = true;
  };
  done.querySelector('.fb-again').addEventListener('click', () => { const k = form.elements.kind.value; reset(); setKind(k); message.focus(); });

  return { setKind, focus: () => message.focus(), reset };
}

/** The home page's dialog: links marked data-feedback open it instead of navigating. */
export function feedbackDialog() {
  const links = [...document.querySelectorAll('[data-feedback]')];
  if (!links.length || typeof HTMLDialogElement !== 'function') return;
  const dialog = document.createElement('dialog');
  dialog.className = 'fb-dialog';
  dialog.setAttribute('aria-labelledby', 'fb-title');
  dialog.innerHTML = `
    <div class="fb-head"><h2 id="fb-title">Send feedback</h2><button class="fb-close" type="button" aria-label="Close">×</button></div>
    <div class="fb-body"></div>`;
  document.body.append(dialog);
  let form = null;
  dialog.querySelector('.fb-close').addEventListener('click', () => dialog.close());
  // A click on the backdrop closes it, like a sheet.
  dialog.addEventListener('click', e => { if (e.target === dialog) dialog.close(); });

  links.forEach(link => link.addEventListener('click', e => {
    if (e.metaKey || e.ctrlKey || e.shiftKey) return;
    e.preventDefault();
    const kind = link.dataset.feedback;
    form ??= feedbackForm(dialog.querySelector('.fb-body'), { kind });
    form.reset();
    form.setKind(kind);
    dialog.showModal();
    form.focus();
    track('feedback_open', kind);
  }));
}
