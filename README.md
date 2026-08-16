<h1 align="center">
  <br>
  NotchFun
  <br>
</h1>

<p align="center">
  <b>Turn the MacBook notch into something worth having.</b>
</p>

<p align="center">
  Media controls, a calendar, a file shelf — and a full clipboard history, all living in
  the black bar you were told to ignore.
</p>

---

## What it is

NotchFun is a macOS menu-bar app that turns the notch on your MacBook display into an
interactive panel. Hover it, click it, or hit a shortcut, and it expands into whatever
you need:

- **Now Playing** — album art, scrubbing, a live audio visualiser, and controls for
  Apple Music, Spotify and anything else that reports Now Playing.
- **Calendar** — today's events at a glance, with a scrollable date strip.
- **Shelf** — a drop zone for files you're moving between apps, with AirDrop and
  Quick Share built in.
- **Clipboard history** — everything you copy, searchable, pinnable, and pasteable
  straight back into whatever app you're in.
- **HUD replacement** — volume and brightness indicators rendered in the notch instead
  of the giant square in the middle of your screen.

## Clipboard history

The newest addition, and the reason this fork exists.

- Remembers text, links, images and files, with the app each clip came from.
- **Search by typing** — just start typing with the tab open.
- **⌘1–⌘9** to grab one of the last nine clips instantly.
- **Pin** the clips you reuse constantly; pinned items never expire and never count
  against the history limit.
- **Paste straight into the active app** — pick an entry and it lands where your cursor
  was, no ⌘V needed.
- Deduplicates repeats, keeps a copy counter, and evicts the oldest entries past a
  limit you choose.
- **Never records passwords.** Password managers mark their copies as confidential
  using the [nspasteboard.org](http://nspasteboard.org) convention, and those are
  discarded before they ever reach memory. History lives only on your Mac, in files
  readable solely by your user account.

It's off by default. Turn it on in **Settings → Clipboard**.

## Install

**Requires macOS 14 Sonoma or later.** Apple Silicon or Intel.

Download the latest `.dmg` from [Releases](https://github.com/lookatsarthak/NotchFun/releases),
open it, and drag NotchFun to your Applications folder.

> [!IMPORTANT]
> NotchFun isn't notarised by Apple, so the first time you open it macOS will say it
> *"could not verify NotchFun is free of malware"*. That is what macOS says about any
> app distributed outside the App Store without a paid Apple Developer account — it is
> not a finding about this app.
>
> **To open it (macOS 15 Sequoia and later):**
> 1. Double-click NotchFun. You'll get the warning — click **Done**, *not* Move to Bin.
> 2. Open **System Settings → Privacy & Security** and scroll to **Security**.
> 3. Next to *"NotchFun was blocked to protect your Mac"*, click **Open Anyway**.
> 4. Authenticate, then open NotchFun again and confirm.
>
> You only need to do this once. The old right-click → Open trick no longer works;
> Apple removed it in macOS 15.
>
> If you prefer the terminal, this does the same thing:
> ```bash
> xattr -dr com.apple.quarantine /Applications/NotchFun.app
> ```

### Permissions

NotchFun asks for permissions only for the features you enable:

| Permission | Needed for |
|---|---|
| **Accessibility** | Pasting into the active app, typing to search the clipboard, and the HUD replacement |
| **Calendars / Reminders** | The calendar tab |
| **Camera** | The mirror preview, if you turn it on |

Nothing is uploaded anywhere. There is no analytics, no account, and no network service.

## Building from source

```bash
git clone https://github.com/lookatsarthak/NotchFun.git
cd NotchFun
open boringNotch.xcodeproj
```

Build the `boringNotch` scheme. Dependencies resolve through Swift Package Manager on
first build.

To produce a distributable disk image:

```bash
scripts/make-dmg.sh
```

## Credits

**NotchFun is a fork of [boring.notch](https://github.com/TheBoredTeam/boring.notch)
by TheBoredTeam.** Essentially all of the notch interaction, media handling, calendar,
shelf and HUD work is theirs — this fork adds clipboard history and assorted fixes on
top. If you like this app, go star theirs; it's the foundation.

The clipboard feature's pasteboard handling, capture filtering, deduplication rules and
synthesised paste are adapted from **[Maccy](https://github.com/p0deje/Maccy)** by
Alex Rodionov (MIT), which solved these problems well long before this existed. Maccy
is an excellent standalone clipboard manager and worth using on its own.

Full third-party licence texts are in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).

## Licence

NotchFun is licensed under the **GNU General Public License v3.0**, inherited from
boring.notch. See [LICENSE](LICENSE).

This is a **modified version** of boring.notch. Changes made in this fork include a
clipboard history feature, a unified tab-switching animation, and fixes to notch
close-gesture handling. As required by GPLv3 §5(a), modified source files carry notices
of the changes, and the complete corresponding source is this repository.

The name "NotchFun" and its icon are not part of the upstream project and are not
covered by upstream's trademarks; equally, "Boring Notch" and its artwork remain
TheBoredTeam's.
