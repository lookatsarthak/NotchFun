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

<p align="center">
  <a href="https://lookatsarthak.github.io/NotchFun/"><b>See it in action →</b></a>
</p>

---

## What it is

NotchFun is a macOS menu-bar app that turns the notch on your MacBook display into an
interactive panel. Hover it, click it, or hit a shortcut, and it expands into whatever
you need:

- **Now Playing** — album art, scrubbing, a live audio visualiser, and controls for
  Apple Music, Spotify and anything else that reports Now Playing.
- **Calendar** — today's events at a glance, with a scrollable date strip, a Join
  button on video calls, and a heads-up in the notch two minutes before one starts.
- **Shelf** — a drop zone for files you're moving between apps, with AirDrop and
  Quick Share built in. Clipboard entries can go on it too.
- **Clipboard history** — everything you copy, searchable, pinnable, and pasteable
  straight back into whatever app you're in.
- **HUD replacement** — volume and brightness indicators rendered in the notch instead
  of the giant square in the middle of your screen.
- **AirPods battery** — left, right and case, shown when you connect them, and beside
  the Mac's own battery while the notch is open.
- **Shortcuts and links** — six actions in Shortcuts.app and `notchfun://` links, so
  caffeine, the clipboard, the notch and your own messages can be driven from an
  automation, a script or Spotlight.

## Shortcuts

NotchFun shows up in Shortcuts.app with six actions: **Show in Notch**, **Set Caffeine**
(with a duration, which a keyboard shortcut cannot express), **Open Notch** (optionally
on a given tab), **Close Notch**, **Paste as Plain Text**, and **Set Clipboard History** —
handy for switching recording off by itself before a screen share.

**Show in Notch** puts a short line in the closed notch for a few seconds, with an
optional SF Symbol and progress ring: build status, a timer, the weather, anything a
script knows. The same works from a link, so any script or terminal can do it:

```bash
open "notchfun://show?text=Build%20passed&icon=checkmark.circle.fill&seconds=5"
```

`notchfun://open?tab=shelf` and `notchfun://close` work too. Messages are text only and
can't open anything, more than five in ten seconds are dropped, and Settings → Shortcuts
can switch them off.

Three of them also answer to Spotlight: *"Toggle caffeine in NotchFun"*, *"Open
NotchFun"*, *"Paste plain text with NotchFun"*.

## AirPods and Bluetooth battery

Off by default; turn it on in **Settings → Battery**.

AirPods and Beats show each earbud and the case, with a bolt while they charge, read
from the same data macOS uses for its own battery widget. No permission is needed, and
the numbers update as they change, without polling. The case appears only while a bud is
in it: the case reports while it's open or holding one, and its last number would
otherwise linger after it's shut.

Other Bluetooth headphones show one number, the lower of the two earbuds if they report
two.

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

Setup switches it on for you, and you can turn it off there or in **Settings → Clipboard**.

**⌘-click** an entry, or right-click it and choose **Add to Shelf**, to put it on the
shelf for dragging into another app later. Images become PNG files.

## Stays light

NotchFun sits at about **0.1% of one CPU core** while idle and uses **about 25–40 MB** of
memory. Open on Home with a paused track, it uses no measurable CPU at all: nothing
redraws until something changes. Twenty screen locks in a row leave it where it started.

Measured with `scripts/soak.sh` on a MacBook Air (M4, macOS 27.2): CPU time over
30-second windows, fresh and after 20 screen-lock cycles, plus memory and the number of
notch windows. Every release has to pass it before it can ship.

## Install

**Requires macOS 26 Tahoe or later.** Apple Silicon, or one of the four Intel Macs
that run Tahoe (2019 Mac Pro, 2019 16-inch MacBook Pro, 2020 13-inch MacBook Pro with
four Thunderbolt ports, 2020 27-inch iMac).

> NotchFun 1.2.1 was the last release for macOS 15 Sequoia. If you are on Sequoia the
> updater will keep you there rather than offer you a build that cannot launch; 1.2.1
> remains downloadable from [Releases](https://github.com/lookatsarthak/NotchFun/releases).

**One line in Terminal** — the quickest way, and the only one that skips the System Settings
step on first launch. Copy it, paste it into Terminal, press Return:

```bash
curl -fsSL https://raw.githubusercontent.com/lookatsarthak/NotchFun/main/scripts/install.sh | bash
```

It downloads the latest release, puts NotchFun in Applications (quitting and replacing an
older copy if you have one), and opens it. [Read the script](scripts/install.sh) first if
you like — it is short. It skips that step because files downloaded by `curl` are not
flagged as coming from the internet, which is what triggers macOS's check. Terminal may
show its own Paste Blocked warning about commands copied from websites; choose Paste
Anyway if you're happy with this one. The script also sends
an anonymous count of the install (NotchFun version, chip, macOS version); set
`NOTCHFUN_NO_ANALYTICS=1` to skip it.

**Homebrew**

```bash
brew install --cask lookatsarthak/tap/notchfun
```

**Or manually** — download the latest `.dmg` from
[Releases](https://github.com/lookatsarthak/NotchFun/releases), open it, and drag
NotchFun to your Applications folder.

> [!IMPORTANT]
> NotchFun isn't notarised by Apple, so the first time you open it macOS will say it
> *"could not verify NotchFun is free of malware"*. That is what macOS says about any
> app distributed outside the App Store without a paid Apple Developer account — it is
> not a finding about this app.
>
> **To open it:**
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

The app uploads nothing. It has no analytics, no account, and no network service.

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
