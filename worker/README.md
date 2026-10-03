# NotchFun backend

A Cloudflare Worker with a D1 database, live at `https://notchfun.lookatsarthak.workers.dev`.
The app never talks to it. Only the website, `install.sh` and the Homebrew cask do.

| Path | What |
|---|---|
| `GET /d/:channel` | Website download buttons. Counts the click, redirects to the latest disk image. |
| `GET /brew/:version` | The Homebrew cask's `url`. Counts the install, redirects to that version's disk image. |
| `GET /i?s=start\|ok\|fail` | Pings from `install.sh`: version, chip, macOS major, and the step a failure stopped at. |
| `POST /e` | Website counts: views and referrer, install section seen, copy, star and feedback clicks. |
| `POST /feedback` | The feedback form. Checked with Turnstile, 5 an hour per visitor, emailed with Resend. |
| `GET /admin` | The numbers. Asks for the admin token. |
| `GET /stats` | The same as JSON, with `Authorization: Bearer <admin token>`. |

Every day at 00:10 UTC it copies GitHub's stars, traffic, referrers and per-file download
counts (GitHub keeps traffic for only 14 days) and deletes the previous day's visitor hashes.

Nothing stored identifies anyone. Unique visitors are counted with a hash of IP and browser
salted with a random value that is deleted after the day ends.

## Secrets

Set with `npx wrangler secret put NAME`:

- `TURNSTILE_SECRET`: the Turnstile widget's secret key
- `RESEND_API_KEY`: a Resend key with sending access only
- `FEEDBACK_TO`: where feedback is emailed; never sent to the browser
- `ADMIN_TOKEN`: for `/admin` and `/stats`; kept in `~/.config/notchfun/admin-token`
- `GITHUB_TOKEN`: fine-grained, read-only, NotchFun only, with Administration read for traffic

## Working on it

```bash
npm install
npm run db:local   # create the local tables
npm run dev        # http://127.0.0.1:8787, with Turnstile test keys from .dev.vars
npm test           # end-to-end checks against the dev server
npm run deploy
```

Schema changes: edit `schema.sql`, then run it locally and with `npm run db:remote`.
