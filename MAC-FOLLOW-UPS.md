<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- Copyright (C) 2026 WittyWilla and contributors -->
# Mac follow-ups: peer to peer everywhere, and one Choose a server page

Written 2026-11-16 on the Windows PC, for Claude on the owner's MacBook. Everything here needs a Mac:
Xcode, the iPhone and Apple TV simulators, and the macOS desktop app. Work through it in order.
Tick each box in this file as you go, commit the ticks, and say in the PR what was run and what wasn't.

**State when this was written: 0.5.2 is released from `main`** (tag `v0.5.2`). It holds everything
below. The owner thinks Apple TV is fine. macOS, iPhone and iPad have **not** been run with these
changes: the checks here are in case they don't match the Apple TV page or don't connect. If a check
fails, fix it on a branch off `main`, with a GitHub issue first, and release it as the next small version
(0.5.3) only with the owner's OK.

**Proven on GitHub's macOS runner (CI, 2026-11-16):** `apple/scripts/build-wittyconnect.sh` builds
`Wittyconnect.xcframework` without `--if-available` (106 libraries in its notices), and the tvOS and
iOS apps compile with it. The desktop app's `.app` was packaged on macOS by `build.yml`, and
`helper-packaged.sh` passed there. Nothing was *run* on a Mac.

## What the owner asked for

1. **Every copy of WittyMediaClient must connect peer to peer, for real.** Windows, macOS, Linux, Flatpak,
   Snap, FreeBSD, Android, iPhone, iPad and Apple TV. A copy that says "its connection helper is missing"
   or "built without peer to peer" counts as broken.
2. **Every copy shows the same Choose a server page**: the one the Apple TV already draws. That means:
   - the app's own mark (the orbitw W on a screen, from `scripts/sync-brand.sh`), never the old purple
     circle with a play triangle;
   - "Choose a server" with "Pick one you've used, one on this network, or connect from anywhere." under it;
   - small-capital section labels with a hairline: YOUR SERVERS, ON THIS NETWORK;
   - round avatars with the server's first letter, a blue dot and a **Peer to peer** chip for a server
     reached from away;
   - the **Connect from anywhere** panel: globe badge, title, one line, the picture (this device, dashed
     line, green Encrypted lock, dashed line, your server), the ways in as real buttons, and three tick
     chips (End to end encrypted, Nothing opened on your router, Invite only).

## What was wrong, and what 0.5.2 fixed (PR 59, merged)

- **0.5.1's desktop installers had no helper.** `release.yml`'s desktop job ran `electron-builder` directly,
  never checked out WittyMediaServer, never had Go, so `wittyconnect` was never built. Fixed: the desktop,
  Flatpak/Snap and FreeBSD jobs check out the server, set up Go, build the helper (no `--if-available`),
  and `scripts/test/helper-packaged.sh` fails any unpacked app without `wittyconnect` and its notices.
- **0.5.1's iPhone and Apple TV apps had no peer-to-peer library.** The apple job's log says
  `NOT BUILT: Go isn't installed`. Fixed in `release.yml` and `build.yml`: `actions/setup-go` before
  `apple/scripts/build-wittyconnect.sh`, and the release runs it **without** `--if-available`, so a
  release without the library fails instead of shipping. **This has not run on GitHub's macOS runner yet.**
- **FreeBSD never had a helper.** The package now carries it beside `app.asar`
  (`/usr/local/share/wittymediaclient/wittyconnect`), and `desktop/p2p.js` `helperPath` looks there when
  the app runs from an `.asar` (FreeBSD runs our archive in the system's Electron).
- **The desktop page was the old design.** `shared/connect/connect.js` and `connect.css` now draw the
  Design 2 page above; the marks come from `shared/brand/mark-client.svg` and `mark-server.svg`, written
  by WittyMediaServer's genicon (server branch `desktop-brand-marks`, which must be merged for
  `scripts/sync-brand.sh --check` to keep them).
- **Android** got the same panel and cards (`android/.../ui/ConnectAnywhere.kt`, `ConnectScreens.kt`).
- **Proven on Windows 11**: `desktop/test/app/p2p-real.js`, all three runs (home, away with the home
  address gone, invite through Join with a link or code). Never yet on macOS with the new page.
- **Proven on the Android phone emulator**: the app built with the library (`-Pp2p=required`) joined a
  server by an invite link pasted under Join with a link or code, and the server logged it connected
  directly. Joining by a shown code needs the server's address book (DHT), which that test kept off.

## What to compare against

The Apple TV's Choose a server page is the reference. The desktop page is `shared/connect` (same
strings in `shared/data/strings.en.json`); the iPhone's is `apple/App/ConnectParts.swift` and
`ConnectViews.swift`. Things most likely to differ on the iPhone, worth looking at first:

- **Strings.** The desktop and Android now use `findTitle` "Choose a server", `findSubtitle` "Pick one
  you've used, one on this network, or connect from anywhere.", `recentServers` "Your servers",
  `foundServers` "On this network", `peerChip`, and the `anywhere*` keys. If the Apple app reads its own
  copy of the strings, check it has the same words (`grep -rn "Choose a server\|anywhereTitle" apple/`).
- **Panel buttons.** Desktop: Join with a link or code, Show a code to type in. Android: Join with a link
  or code (a screen that takes a pasted link and also shows a code), Scan a QR code, Enter an address.
  The iPhone should offer the same ways in; section 6 below.
- **Colours.** Peer blue `#0a84ff`, Encrypted green `#3ad29f`, as the desktop's `--peer` and `--ok`.
- **The lockup.** The client mark (screen on a stand, W in a ring, mint dot), never the old purple circle
  with a play triangle.

## 1. Get the code

```bash
cd ~/<where the repos are>/WittyMediaClient
git fetch origin && git switch main && git pull
cd ../WittyMediaServer
git fetch origin && git switch v0.8.0-alpha && git pull
```

The server's `v0.8.0-alpha` has genicon writing `shared/brand/mark-*.svg` (PR 393). The release built the
helper and library from the server's default branch (`master`); either works for these checks.

- [ ] Both checked out side by side (`WittyMediaClient` and `WittyMediaServer` in one folder).

## 2. The brand files are current

```bash
cd WittyMediaClient
sh scripts/sync-brand.sh --check
```

It must say every file is up to date. If it lists `shared/brand/*.svg` as missing, the server branch
isn't `desktop-brand-marks`. If it lists many PNGs as different, that is the PC's rasteriser, not a
design change: run `sh scripts/sync-brand.sh` on the Mac, look at `git diff --stat`, and commit only
if the pictures look the same.

- [ ] `sync-brand.sh --check` passes on the Mac.

## 3. macOS desktop app: the page, and the helper inside the app

```bash
cd desktop
npm ci --ignore-scripts --no-audit --no-fund
npm test
WITTYMEDIASERVER_SRC="$PWD/../../WittyMediaServer" node scripts/build-wittyconnect.mjs mac-arm64
WITTYMEDIASERVER_SRC="$PWD/../../WittyMediaServer" node scripts/build-wittyconnect.mjs mac-x64
npm run sync
CSC_IDENTITY_AUTO_DISCOVERY=false npx electron-builder --mac --dir -c.directories.output=out-p2p-check
bash ../scripts/test/helper-packaged.sh out-p2p-check
```

`helper-packaged.sh` must print `ok:` for `WittyMediaClient.app/Contents/Resources/wittyconnect` and
its notices file. Then:

```bash
mkdir -p /tmp/wmc-shots
WMC_SHOTS=/tmp/wmc-shots npx electron test/app/run.js journey
WMC_SHOTS=/tmp/wmc-shots npx electron test/app/run.js tv
```

Open `/tmp/wmc-shots/list-empty.png`, `list-found.png`, `list-recent.png` and `tv-list.png`. Compare
with the Apple TV page (run the tvOS app in the simulator, or the owner's screenshot). Check:
the client mark in the lockup (screen on a stand, W in a ring, mint dot), "Choose a server" centred,
YOUR SERVERS / ON THIS NETWORK with hairlines, the panel with the dashed-line picture and green
Encrypted, the three tick chips. On a Mac the Help menu is in the menu bar; the in-window Help test is
skipped there.

- [ ] `npm test` passes on macOS.
- [ ] `helper-packaged.sh` passes for the `.app`.
- [ ] `run.js journey` and `run.js tv` pass, and the pictures match the Apple TV page.

## 4. macOS desktop app: peer to peer for real

The same three runs the PC passed. A server of your own on a port of its own: never the owner's
installed server, never port 9797.

```bash
cd ../WittyMediaServer
GOWORK=off go build -o /tmp/wms-p2p/wms ./cmd/wittymediaserver
cp -R web/dist /tmp/wms-p2p/ 2>/dev/null || true   # the server needs its built web pages; build them (cd web && npm ci && npm run build) if web/dist is empty
```

Then follow `desktop/test/app/p2p-real.js`'s header. The PC's script, which works and can be copied to
bash on the Mac nearly as is (change paths, use `python3`):

1. Start the server: `WMS_NO_DIALOG=1 WMS_NO_BROWSER=1 /tmp/wms-p2p/wms serve -data /tmp/wms-p2p/data -listen 127.0.0.1:19511 -open-browser=false &`
2. Wait for `curl -fsS http://127.0.0.1:19511/api/health`.
3. `POST /api/setup` with `{"name":"owner","password":"<a long one>","device":"check","acknowledgedLegal":true}`, keep the `token`.
4. `POST /api/v1/setup/complete` with `{}`.
5. `PUT /api/settings` with `{"saveMetadata":"0","lanDiscovery":"0"}`.
6. `PUT /api/v1/p2p/settings` with `{"enabled":true,"accept":true,"port":0,"layers":{"dht":false,"relay":false,"holePunch":false,"portMap":false,"ipv6":false},"devicesOnly":true,"relayKbps":4000,"relayForOthers":false,"staticRelays":[]}`.
7. `GET /api/v1/p2p` must give a `serverId`.
8. A forwarder on 127.0.0.1:19512 to 19511 (the Python one in `apple/scripts/p2p-check.sh`).
9. With `WMC_SERVER=http://127.0.0.1:19512 WMC_DIRECT=http://127.0.0.1:19511 WMC_USER=owner WMC_PASSWORD=... WMC_TEST_DIR=/tmp/wms-p2p/app WITTYCONNECT=$PWD/../WittyMediaClient/desktop/bin/mac-arm64/wittyconnect`:
   `npx electron test/app/p2p-real.js --phase=home`, stop the forwarder, `--phase=away`, then `--phase=invite`.

Every step must print `ok`. The invite run now goes through **Join with a link or code** in the
Connect from anywhere panel, so it also proves the new button.

- [ ] home passed on macOS.
- [ ] away passed on macOS (found peer to peer with the home address gone, still signed in).
- [ ] invite passed on macOS.
- [ ] `docs/PLATFORMS.md`'s desktop rows say so, with the date.

## 5. iPhone, iPad and Apple TV: the library is in, and peer to peer works

The Apple app already draws the Design 2 page (`apple/App/ConnectParts.swift`, `ConnectViews.swift`).
What failed is the library: 0.5.1 shipped without it. First prove it builds:

```bash
cd ../WittyMediaClient
WITTYMEDIASERVER_SRC="$PWD/../WittyMediaServer" bash apple/scripts/build-wittyconnect.sh
ls apple/Frameworks
```

It must build **without** `--if-available` and leave the Wittyconnect framework in `apple/Frameworks`.
If it fails, that failure is what the release would hit: fix it here, in the script or the server's
`scripts/build-wittyconnect-mobile.sh`, before anything else.

Then the real checks, which build their own server and need nothing of the owner's:

```bash
WITTYMEDIASERVER_SRC="$PWD/../WittyMediaServer" bash apple/scripts/p2p-check.sh tvos
WITTYMEDIASERVER_SRC="$PWD/../WittyMediaServer" bash apple/scripts/p2p-check.sh ios
```

Both must pass at home, away and invite. Look at the pictures in `apple/build/p2p-check`.

- [ ] The library builds without `--if-available`.
- [ ] `p2p-check.sh tvos` passes.
- [ ] `p2p-check.sh ios` passes.
- [ ] The iPhone's Choose a server page shows the Connect from anywhere panel with the picture, Join with
      a link or code, Scan a QR code and Enter an address, and the three tick chips. "Join with a link or
      code" must not say "built without peer to peer".

## 6. iPhone and the desktop: the same ways in

The desktop panel has **Join with a link or code** and **Show a code to type in** (a code this device
shows, which someone signed in types into the server). Apple TV has its code; the iPhone panel has
Join (paste a link), Scan and Enter an address. Check that an iPhone that has never met the server can
also show a code (Join from away by code), as Android and the desktop can. If it can't, add a "Show a
code to type in" button to `remoteWays` on iOS that opens the same join-by-code screen the TV uses.

- [ ] iPhone can join by a code it shows, or a button for it is added and tested in `p2p-check.sh ios`.

## 7. Before a release

- [ ] Download 0.5.2's macOS `.dmg` and the iPhone `.ipa` from the GitHub release, and check the
      helper is inside: `WittyMediaClient.app/Contents/Resources/wittyconnect`, and
      `Payload/*.app/Frameworks/Wittyconnect.framework` (or the library linked into the app binary).
- [ ] If anything above needed a fix: bump to 0.5.3 (memory: version bumps), say so in CHANGELOG.md,
      and release it with the owner's OK.

## 8. Interface parity with the server's 0.8.1 audit (issue 60)

Added 2026-11-18 from the Windows PC. The server's interface audit (WittyMediaServer issue 438, its
`docs/UI-PLATFORMS.md`) fixes problems once, in tokens, SDUI specs and shared parts. On Windows, PR 62 made
the desktop connect screen and Android follow it. These need the Mac. Tick each and say in the PR what ran.

- [ ] **Hero scrim on iPhone, iPad, Apple TV and the macOS app's native screens.** `shared/data/themes.json`
  now has each theme's `heroScrim`, and WittyKit's `Theme.heroScrim` is already read from the server's
  `tv.heroScrim`, but nothing draws with it. Every hero and title header that puts words over a picture
  (`App/ItemPages.swift`, `App/BrowseViews.swift`, `App/MobileShell.swift`, the SDUI hero) should have a scrim
  in the page's own colour, at least `heroScrim` where the words are, fading out past them; words at full
  colour (no 0.86 opacity). Android's `ui/HeroScrim.kt` is the reference: with the old 0.72 it is exactly the
  shade the phone had, so only themes that raised it look different.
- [ ] **Read the new theme colours.** `themes.json` also carries `focus`, `scrim`, `onImage`, `borderStrong`,
  `accentHover` and `controlLine`. Decode them (Codable ignores them today) and use `focus` for the ring.
- [ ] **Page top under the bar.** A page's first line is 16pt (`space.4`) under the floating bar, and a hero
  that opens the page goes under the bar (the audit's R7). Check Home, a library, Settings and a title page
  on iPhone, iPad and Apple TV, in light, dark and an Aero theme.
- [ ] **Pictures never stop on a line** (server PR 411): a hero's foot fades into the page; a hero below
  setup notices fades at its top too. Check Home and a title page.
- [ ] **Focus ring:** Apple TV 4 units, 1.06, lifted 6 (`DesignTokens.Tv.Focus`); iPad with a keyboard 3pt
  (`focus.input.keys`). Check it is visible on every theme, including Contrast and the Aero themes.
- [ ] **macOS desktop app:** the server's page under the 32px title bar at phone and desktop widths, and in
  full screen (no title bar, no gap). The connect screen now loads `theme.css`: check it still opens.
- [ ] **Android emulator pass** if it wasn't done on the PC: Home's billboard and a title header in Default,
  Light, Contrast and Aero Sunset; page top under the bar; the TV rail's focus ring.

## Never

- Never use or stop the owner's installed server (port 9797) for any of this.
- Never write competitor product names in code, docs or UI.
- Never push, tag or release without the owner's OK, and make a GitHub issue first.
