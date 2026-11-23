<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- Copyright (C) 2026 WittyWilla and contributors -->
# Mac follow-ups

Newest first. Each section is one pass that needs a Mac: Xcode, the iPhone and Apple TV simulators, the macOS desktop
app. Work through the newest first, tick each box here as you go, commit the ticks, and say in the PR what ran and what
didn't. The GitHub issues labelled `mac` point at these sections.

## WittyMediaClient 0.6.0: what's left for the owner (2026-11-23)

0.6.0 was tagged from the Windows PC with `tag.yml`, and `release.yml` built and published every package: Windows,
macOS, Linux, Flatpak, Snap, FreeBSD, the Android sideload APKs and the unsigned iPhone/iPad and Apple TV IPAs. Nothing
is signed with a real certificate (as in every release so far; see `docs/OWNER-STEPS.md`). The release notes say the
Apple builds weren't tested on Apple devices yet. Before the next update, on the MacBook:

- [ ] **1.** Download `wittymediaclient-0.6.0-ios.ipa` and the Apple TV IPA from the GitHub release, sign and install
  them with AltStore, SideStore or Sideloadly, and check that they start and connect to a 0.8.1-alpha server.
- [ ] **2.** Work through the two sections below in the simulators (the centred computer-settings card, and the 0.8.1 UI
  changes on Apple), then the older "0.8.1-alpha: what the Mac must do".
- [ ] **3.** Open the macOS desktop app from the release (unsigned: right-click, Open, the first time), connect to the
  server, and play a film, a song and live TV.
- [ ] **4.** Anything else that needs your own accounts (an Apple Developer certificate and notarisation, a Play Store
  or App Store listing) is optional and listed in `docs/OWNER-STEPS.md`; none of it is needed for this release.
- [ ] **5.** Tell the next session what you found, so the fixes go into 0.8.2-alpha.

## 0.8.1-alpha: the centred card for a computer's settings (2026-11-22)

Written 2026-11-22 on the Windows PC. Every screen Apple TV sends to a computer (the server's desktop-only settings,
and a module's page Apple TV can't show) is now one centred card, as the sign-in screens are: the server's name small
under the glow, the setting's symbol and name, one line, the QR code large on a white tile with "or open" and the
address under it, what is set now in a card, **Back** focused, and the server's own words at the foot. One view,
`OnAComputerCard` in `apple/App/ModulePages.swift`, draws both `EditorOnComputerPage` and `ModuleOnPhonePage`.
Compiled by CI's macOS runner only. Android TV's twin ran here: compare `docs/mac-081/tv-card-android-1080p.png`.

- [ ] **1.** Apple TV simulator (1080p), against the 0.8.1 server of the section below, signed in as its administrator.
- [ ] **2.** You → **Libraries**, **Metadata and artwork**, **Live transcoding**, **Remote Access**, **Backup**: each card
  is centred, the QR code is the largest thing on it and scans with a phone, the address under it is readable from a
  sofa, the "set now" card shows (Libraries: the count and kinds; Backup: the schedule), and **Back** has focus.
  Menu and Back both return to You. Nothing on it names a keyboard key.
- [ ] **3.** A long name and address: rename a library to a long name, open Libraries; and open the card through a
  long address (a WittyPlay library's settings): the heading wraps to two lines at most, the address wraps between
  its parts, Back still shows without scrolling.
- [ ] **4.** A module's page (Statistics, or the Folder browser if installed): the same card, saying to open it on a
  phone or computer, with no "set now" card.
- [ ] **5.** Light theme (You → Look and theme → Light): the glow, the white tile and the words still read.

## 0.8.1-alpha UI changes on Apple: what the Mac must check (2026-11-22)

Written 2026-11-22 on the Windows PC, for Claude on the owner's MacBook. After #67, the server's 0.8.1 UI changes
(karaoke #524, backdrops #545, the mini player #523, menu placement #538, and more) were ported to the Apple apps in
WittyMediaClient #82 (branch `apple-081-ui`). [docs/PARITY-0.8.1.md](docs/PARITY-0.8.1.md), under "The UI changes
after client #67", lists every change and where it stands: ported, already so, web only (free), or owned by another
session. Do this section before the older one below; they can share the server from its step 2.

**Written on Windows, never run on any Apple device or simulator.** WittyKit's part was compiled and its tests run with
Swift 6.1 on Linux (749 pass). The apps were only compiled, by CI's macOS runner:

| File | What changed |
|---|---|
| `apple/WittyKit/Sources/WittyKit/VoiceFx.swift` (new) | Voice settings' controls, ranges, the nine presets and As recorded, what's kept, and the numbers for the audio units |
| `apple/WittyKit/Sources/WittyKit/KaraokeStems.swift` | The voice is out each time karaoke starts (`sing` is true), `toggleGuide`, `guideLevel` 0.2, `pristine`, `voiceParts` |
| `apple/WittyKit/Sources/WittyKit/HeroFade.swift` (new) | The fade curve of #545 |
| `apple/App/StemPlayer.swift` | **New audio units**: the voice through its bus, EQ (low cut, warmth, presence, air), the dynamics processor, doubling and echo delays, reverb and pan; the music through its bus and EQ (bass, treble, room for the voice) |
| `apple/App/KaraokeStems.swift` | `fx` and its store, `toggleGuide`, `hearVoice`, `voiceOut`, `waiting` |
| `apple/App/KaraokeStemsViews.swift` | The Mix's contents, `KaraokeVoiceFxPanel`, `KaraokeChip`, Apple TV's `KaraokeStemsPanels` |
| `apple/App/MusicPanels.swift` (`KaraokeView`) | The first screen, the Mix and Voice settings as a side panel or sheet, idle hiding, the visualizer's styles |
| `apple/App/MusicPlayerUI.swift`, `Listening.swift` | The iPad bar's More menu (Lyrics, Karaoke, Visualizer), a solid bar backing |
| `apple/App/HeroFadeMask.swift` (new), `ItemPages.swift`, `SDUI/SDUIHeader.swift`, `BrowseViews.swift` | Backdrops masked, not painted over |
| `apple/App/SDUI/SDUICenter.swift` | The strip of sections: of what's placed in More, only the libraries and Collections |
| `apple/App/TvWordsView.swift` | Apple TV's karaoke screen uses the new bar |

Reference pictures (the website after each change) are in `docs/mac-081/ui/`, with more on the PC under
`D:\projects-0.8.0\_status\082-fixes\` (`karaoke\`, `hero-edges\`, `layout\`).

### Steps

- [ ] **1. The code and a server.** `git switch apple-081-ui` in WittyMediaClient (or `v0.8.1-alpha` once #82 has
  merged), and the server's `v0.8.1-alpha`, built and run as step 2 of the section below (port 19555, fresh data, a
  film with a backdrop, and an album). For karaoke, the server must make the parts: Settings → Lyrics and music
  information → karaoke on (the quick version needs nothing installed). Using the same server, set Demucs up as the
  server's own Mac step 4 says, then check the separated version too.
- [ ] **2. WittyKit's tests on macOS**: `cd apple/WittyKit && swift test`. Expected: all pass, among them the new
  `VoiceFxTests` and `HeroFadeTests`, and `KaraokeStemsTests` with the voice out by default.
- [ ] **3. Build and open the apps**: `bash apple/scripts/check-on-mac.sh`. Expected: every line of
  `apple/build-logs/report.txt` says `ok`.
- [ ] **4. iPhone (simulator), karaoke.** Play a song from the album, open the player, **Karaoke**.
  - [ ] The first screen is the words, **Previous line**, **Play**, **Next line**, **Guide voice** and **Mix**, with
    nothing else on the bar. Compare `docs/mac-081/ui/karaoke-phone-kar-first-screen.jpg`.
  - [ ] **The singer is out** as it starts, on the quick version and the separated one, even if the Voice slider was
    left at 100% last time. **Guide voice** brings them back quietly (20%), and a second press takes them out again.
  - [ ] **Mix** opens a sheet from the bottom (it can be dragged taller): Voice, Background Music and Track, **Voice
    off**, **Guide voice**, **Reset** (dimmed until something moves), "Separated." or "Quick version." with the
    note, the Key and words' timing steppers, Follow along / Read, and **Voice settings**. Compare
    `karaoke-phone-kar-mix.jpg`. While the version is being made, the same sliders show dimmed with "Preparing
    karaoke… n%".
  - [ ] **Voice settings**: Presets and Advanced. Presets has three rows (Female vocal, Mid-range vocal, Low vocal), each
    with High, Medium and Low, and **As recorded**. Choosing one is heard straight away: listen for the echo and room
    on Female vocal, High, against As recorded. Compare `karaoke-phone-kar-voice-presets.jpg`. With the voice out it
    says so, with **Hear the voice**. Advanced on a phone shows only the "bigger screen" note. Close the app and
    open karaoke again: the preset is kept, and the voice is out again.
  - [ ] **Idle**: leave it 4 seconds and the title row and "Behind the words" fade away; the words don't move. A tap
    on the words brings them back, and another hides them. With VoiceOver on, they never hide.
  - [ ] **Behind the words → Visualizer**: Bars, Waves, Drift and **More** sit under it. Choosing one changes the
    visualizer behind the words, and Now Playing's visualizer is the same one afterwards.
  - [ ] **Sound check (the real risk)**: with Female vocal, High chosen and Echo moved in Advanced on an iPad, the sound
    never drops out and never clips while the parts play, seek, pause and change song. If the dynamics processor
    (`kAudioUnitSubType_DynamicsProcessor`) misbehaves, say so and bypass it rather than ship silence.
- [ ] **5. iPad (simulator), on its side.**
  - [ ] Karaoke's **Mix** and **Voice settings** open as a panel at the right, with the words still showing. Compare
    `karaoke-desktop-kar-mix.jpg` and `karaoke-desktop-kar-first-screen.jpg`. Voice settings is on the bar here.
    Advanced lists every control in four groups, with its value ("+3 dB", "320 ms", "Centre").
  - [ ] **The music bar** (the wide one along the bottom): after the queue and the volume there is **⋯ More** with
    Lyrics, Karaoke and Visualizer. Each opens the full player at that part. Compare
    `layout-miniplayer-more-menu-open-1440.jpg`.
  - [ ] In **Aero Day** or another glass theme, no page text reads through the bar.
- [ ] **6. Backdrops (#545)**, on iPhone and iPad, in Witty, Light, Aero Sunset and Aero Aurora (scene themes):
  - [ ] Open a film. The picture at the top fades into the page with no straight line where it ends, and on an iPad
    no hard edges at the sides. The title's words still read where they overlap it. Compare
    `docs/mac-081/ui/hero-edges-real-phone.jpg` and `hero-edges-after-widths.jpg`.
  - [ ] An SDUI title page (a show, a game) the same.
- [ ] **7. The strip of sections (#538)**, on iPhone: with WittyIntegratedFileBrowser or another module that places
  itself in More, and an administrator signed in: the strip along the top lists the libraries and Collections, not
  Server folders. Server folders is in Menu. Compare `537-nav-after-phone.jpg`.
- [ ] **8. Apple TV (simulator), with the remote only.**
  - [ ] Now Playing → **Karaoke**: the bar shows **Guide voice**, **Mix** and **Voice settings**. Each opens below; Up
    and Down move between rows, Left and Right a slider 5% at a time. Voice settings' presets are reached with the
    arrows, and Advanced says to use a computer. Compare `karaoke-tv-kar-voice-presets.jpg` and
    `karaoke-tv-kar-mix.jpg`.
  - [ ] Home's billboard and a title's page: the picture fades out at the bottom with no line, in Witty and Aero
    Sunset. The words at the left read as before.
  - [ ] The top menu: if a module placed in More (Server folders) shows in the scrolling row, say in the PR whether it
    should move behind a More item instead. That's a design question for the owner, not fixed here.
  - [ ] No keyboard shortcut shows anywhere (the standing rule). The only remote hints are the game player's controls
    and "Play/Pause twice for live".
- [ ] **9. The macOS desktop app.** Nothing native changed. With the server from step 1, check these show as the
  website does, since they are the website: karaoke's new first screen and Mix (press **K** on a song), the mini
  player's More menu, a film's backdrop in Aero Sunset, and in `--tv` mode (`open -a WittyMediaClient --args --tv`)
  no keyboard hints on the karaoke screen. The menu bar's zoom shortcuts are the system's own and are fine.
- [ ] **10. After #531 (readability) merges** into the server's `v0.8.1-alpha`, regenerate the shared theme data
  (`WMS_THEMES=../WittyMediaServer/themes node shared/scripts/build-themes.mjs`, as ci.yml checks it and client commit `0dbb225` did; any computer can do this part), commit it, and check
  the selected row and badges in Witty, Light and Paper on iPhone and Apple TV.
- [ ] **11. Report**: tick these boxes, add the pictures from steps 4 to 8 to `docs/mac-081/ui/` with `-mac` in their
  names, and say in #82 (or a follow-up PR) what ran and what was fixed. Close or update the `mac` issues: #68
  (iPhone and iPad), #69 (Apple TV), #70 (macOS desktop).

Not ported (gaps listed in the parity table): karaoke's Controls menu, Album art beside the words, the theme's
`tv.heroScrim` on Apple (step 8 below), and Apple TV's album page (waiting for tv-album-081).

---

## WittyTV guide and Who's watching? on Apple TV (not done on Windows)

The Android TV changes in this pass have no Apple TV twin yet, and Swift can't be compiled on the Windows PC. For the Mac:

- [ ] `apple/App/TvGuide.swift`: start the preview no wider than 440 (as `GUIDE_PREVIEW_START` in `tv/TvGuideHero.kt`), keep the hero's top padding small when the guide sits under the tab bar, give the grid a whole number of rows, and drop the always-on dock under the grid.
- [ ] Add a **Shortcuts** button next to the set button in the guide's bar that shows or hides the dock (Look, Day, Channels, Filter, Recordings, Record, More info, Help) under it. Closed by default, remembered per device, Menu opens and focuses it, Back closes it. No keyboard letter badges on tvOS; move the "Up and Down change channel…" hint line into Help.
- [ ] `apple/App/ConnectViews.swift` (Who's watching, around line 717): it already centres one row; check it against `WhoStep` in Android's `TvWhoPage` (title with ’, "Sign in with your phone" from the new `usePhone` string, Change server as a link, smaller faces above four profiles) at 1080p and 720p with 1, 3 and 8 profiles.

## 0.8.1-alpha: what the Mac must do

Written 2026-11-19 on the Windows PC, for Claude on the owner's MacBook. WittyMediaServer 0.8.1-alpha added TV mode
levels, skip parts from `.wittyinfo` files, karaoke's three-slider Mix and more; [docs/PARITY-0.8.1.md](docs/PARITY-0.8.1.md)
says, feature by feature and platform by platform, what the apps already had, what was done on Windows, and what is left.
This section is the Mac's part of it. The server's own Mac items (its installer and service, the data folder, the
graphics paths, karaoke on Apple silicon) are in WittyMediaServer's `MAC-FOLLOW-UPS.md`, under the same heading.

Issues: iPhone and iPad #68, Apple TV #69, the macOS desktop app #70 (server: wittywilla/WittyMediaServer#527 to #530).

**Written on Windows, never run on any Apple device or simulator** (WittyKit's part was compiled and its tests run with
Swift 6.1 on Linux; the apps were only compiled, by CI's macOS runner):

| File | What changed |
|---|---|
| `apple/WittyKit/Sources/WittyKit/MediaSkips.swift` | `segments`, previews, parts someone named ("Skip dream sequence"), a scene after the credits, parts only marked, `SkipPrefs.fileAuto` and `SkipPrefs.none` |
| `apple/WittyKit/Sources/WittyKit/KaraokeStems.swift` | The Mix is Voice, Background Music (`music`) and Track (`track`); new gains |
| `apple/WittyKit/Sources/WittyKit/TvLevels.swift` (new), `SDUI/SDUICatalog.swift` | The server's TV levels table from the catalogue, `tvSummary` |
| `apple/App/MediaPages.swift` | You → Playing: Previews, Other parts someone named, What the video's own file says to skip |
| `apple/App/MediaSkips.swift` | A watch party skips nothing by itself, not even what a file asks |
| `apple/App/KaraokeStemsViews.swift` | "Voice" and "Mix" on the bar; the Mix lists the three sliders |
| `apple/App/ModulePages.swift`, `Shell.swift`, `SDUI/SDUIActions.swift` | Apple TV: `EditorOnComputerPage`, the card for an editor the server keeps for a computer, and SDUI routes to one go there |

The same changes on Android **ran** on the emulators here: compare against the pictures in `docs/mac-081/`, named
below (all of them, desktop included, are in `D:\projects-0.8.0\_status\082-fixes\clients\` on the PC).

### Steps

- [ ] **1. The code.** WittyMediaClient's PR from branch `clients-081-parity` (into `v0.8.1-alpha`), and the server's
  `v0.8.1-alpha`, side by side:

  ```bash
  cd ~/<where the repos are>/WittyMediaClient
  git fetch origin && git switch clients-081-parity && git pull
  cd ../WittyMediaServer
  git fetch origin && git switch v0.8.1-alpha && git pull
  ```

  If the PR is merged by then, use `v0.8.1-alpha` in both.

- [ ] **2. A 0.8.1 server on the Mac**, with fresh data, on port 19555 so it can't be mistaken for another:

  ```bash
  cd ~/<where the repos are>/WittyMediaServer
  (cd web && npm ci && npm run build)
  go build -o /tmp/wms-081/wittymediaserver ./cmd/wittymediaserver
  /tmp/wms-081/wittymediaserver serve -data /tmp/wms-081/data -listen 0.0.0.0:19555 -open-browser=false
  ```

  Open `http://127.0.0.1:19555` in Safari and go through setup: an account, metadata writing off, and two libraries,
  one with a film or episode **three minutes long or more**, one with an album. Then give that video the test
  `.wittyinfo` from this repository (recap 0:00 to 0:15, intro 0:20 to 0:40, a part named "Dream sequence" 0:50 to
  1:10 that skips itself, a preview at 1:20 that is only marked, credits 2:00 to 2:50 with a scene after them from 2:30):

  ```bash
  TOKEN=$(curl -s -X POST http://127.0.0.1:19555/api/login -H 'Content-Type: application/json' \
    -d '{"name":"<you>","password":"<your password>"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
  ITEM=<the video's id, from its page's address>
  curl -s -X PUT "http://127.0.0.1:19555/api/wittyinfo/item/$ITEM" -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d "{\"info\": $(cat ../WittyMediaClient/docs/mac-081/skip-test.wittyinfo.json)}"
  curl -s "http://127.0.0.1:19555/api/media/$ITEM/markers" -H "Authorization: Bearer $TOKEN"
  ```

  Expected: the last answer has `segments` with six parts and `"source":"wittyinfo"`.

- [ ] **3. WittyKit's tests on macOS.**

  ```bash
  cd ~/<where the repos are>/WittyMediaClient/apple/WittyKit && swift test
  ```

  Expected: every test passes, `MediaSkipsTests`, `KaraokeStemsTests` and the new `TvLevelsTests` among them. On Linux
  they did; the Mac is the first to run them with Apple's own Foundation.

- [ ] **4. Build both apps and open them in the simulators.**

  ```bash
  cd ~/<where the repos are>/WittyMediaClient && bash apple/scripts/check-on-mac.sh
  ```

  Expected: every line of `apple/build-logs/report.txt` says `ok`. A `FAIL building` lists the errors: fix them here
  (CI's macOS runner compiled these files, so a failure is most likely a newer Xcode).

- [ ] **5. iPhone (simulator), against the server from step 2** (`http://<the Mac's address>:19555`, or
  `http://127.0.0.1:19555` from the simulator):
  - [ ] **You → Playing (Skip buttons):** Intros, Recaps, Credits, Adverts, Previews, Other parts someone named, all
    "Ask"; then **What the video's own file says to skip**, "By itself". Compare `docs/mac-081/android-phone-07-playing-on-this-device.png`.
  - [ ] **Play the video from step 2** from the start and leave it: **Skip recap** shows at 0:05 and goes to 0:15;
    **Skip intro** at 0:25; at 0:50 it jumps to 1:10 by itself, saying **Skipped dream sequence** with Undo (Undo goes
    back to 0:50 and the part then plays); at 1:25 there is **no** button (the preview is only marked); at 2:05
    **Skip credits** goes to **2:30**, the scene after them, not to the next episode.
  - [ ] **Karaoke:** play a song of the album, open the player, **Karaoke**. While it's made it says "Preparing
    karaoke…"; then the bar has **Voice** (a slider), **Sing** and **Mix**. Mix shows Voice, Background Music and
    Track at 100%, "Quick version" and Reset. Compare `docs/mac-081/android-phone-11-karaoke-mix.png`. Background Music to 0: the
    music goes and the voice stays. On the quick version the music can't go below the voice on Apple (the gain stops
    at nothing; Android and the website take the music out of the whole song): say whether that is good enough.
  - [ ] **Theme contrast:** You → Theme, try Witty, Light, High contrast, Teletext and Aero Day. The Skip buttons,
    the karaoke Mix and the new rows read in each.

- [ ] **6. iPad (simulator):** the same as step 5, sideways, quickly: the Mix sits in the middle and no row is cut off.

- [ ] **7. Apple TV (simulator), with the remote only** (arrows, Select, Menu: the Siri Remote window in the simulator):
  - [ ] **The skip check of step 5**, with the remote: each button takes focus when it shows, Select skips.
  - [ ] **TV levels:** open a server editor the table keeps for a computer: Home's **Your libraries → Manage**, or
    You → Libraries where it's listed. Expected: **Change this on a computer** with the server's sentence ("To change
    this, use the WittyMediaClient app on a Windows or Mac computer, or a web browser."), what is set now ("2 libraries",
    "movies 1, music 1"), and a QR code with the server's address on your network. Compare
    `docs/mac-081/android-tv-05-libraries-card.png`. A page the table doesn't list (one of a module's) still shows the old "Open this
    on a phone or computer" card. If no route on Apple TV reaches such an editor, say so in the PR.
  - [ ] **Karaoke with the remote:** Down from the bar reaches the Mix; Up and Down move between Voice, Background
    Music, Track and Reset; Left and Right move a level 5% at a time. Compare `docs/mac-081/android-tv-07-karaoke-remote.png`.
  - [ ] **10-foot contrast and focus:** in Witty, Light, High contrast and Teletext, the focus ring shows on every
    row, slider and button of these screens.

- [ ] **8. The hero scrim on Apple (not done on Windows).** WittyMediaServer #444 puts words over a picture on a scrim
  in the theme's own page colour, at least the theme's `tv.heroScrim`. Android does this in `ui/HeroScrim.kt`; the
  Apple apps still draw their own fixed fades (`apple/App/SDUI/SDUIHeader.swift` around lines 176 and 345,
  `BrowseViews.swift` 401, `GamePage.swift` 548). Port `HeroScrim` (read `tv.heroScrim` with the theme, default 0.72),
  use it in those places, and check Home's hero and a title's page in Light and Aero Sunset: dark words on a light
  wash, light words on a dark one.

- [ ] **9. The macOS desktop app.**

  ```bash
  cd ~/<where the repos are>/WittyMediaClient/desktop
  npm ci && npm test && npm run test:app
  WMC_SERVER=http://127.0.0.1:19555 WMC_USER=<you> WMC_PASSWORD=<your password> WMC_SHOTS=/tmp/wmc-mac npm run test:real
  WMC_SERVER=http://127.0.0.1:19555 WMC_USER=<you> WMC_PASSWORD=<your password> WMC_SHOTS=/tmp/wmc-mac-tv npm run test:real -- --tv
  ```

  Expected: `npm test` passes; `test:real` says "All 8 passed" and with `--tv` "All 11 passed". The TV menu should
  match `docs/mac-081/desktop-tv-09-menu.png`. Then `npm run package:mac`, open the `.dmg`, start the app with `--tv`
  (`open -a WittyMediaClient --args --tv`), go to Settings → Libraries: it should say **Leave TV mode to change this**
  with a **Leave TV mode** button (a computer in TV mode, never the QR card).

- [ ] **10. Report:** tick these boxes, commit with the pictures of steps 5 to 9 (in `docs/mac-081/`), push, and say in
  the PR what ran, what didn't, and what was fixed. Close the `mac` issues this section answers.

---

## 0.5.2 (2026-11-16): peer to peer everywhere, and one Choose a server page

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

## TV levels (WittyMediaServer #469)

Written 2026-11-18 with WittyMediaServer #469 (what a TV offers: the server's TV levels, its `docs/TV-MODE.md`).
Android TV was done on the PC. Nothing below was run; each item needs a Mac or Plasma Bigscreen.

**For Claude on the Mac:** work through this list and tick items off here.
Merge nothing and don't release or tag without the owner's OK.

### Apple TV (tvOS)

1. Decode `tvLevels` from `GET /sdui/catalog` (screens by address, with `:name` and a trailing `*`, first match
   wins; parts by id), as `android/.../net/TvLevels.kt` does. Keep the old behaviour when it is missing.
2. Wherever tvOS shows `OpenOnPhone` or `ModuleOnPhonePage` for a server page, decide by the table instead: a
   `desktopOnly` screen is the card; anything else the app can draw itself is drawn. Console and gaming screens
   (controllers, mapping, game settings) must never be the card.
3. The card: the table's `note` as its words, the address, the QR code, and the lines of
   `GET /sdui/tv-summary/{summary}`. When the server address is one only the TV can reach, use the first of the
   summary's `addresses` in the QR code. Focus starts on Back; Menu leaves.
4. An SDUI page whose rendered document says `page.tv` = `desktopOnly` or `view` is the card (with the page shown
   read only under it for `view`). Module settings pages and rows with `tv` show their values read only on tvOS.
5. The app's own editors on tvOS (layout, name and logo, making a canvas, if tvOS has them) are the card when the
   parts `app.layout-editor`, `app.brand-editor` and `title.canvas` are `desktopOnly`.
6. iPhone, iPad and the Mac app keep every screen: only tvOS follows the table.

### Plasma Bigscreen

7. Plasma Bigscreen shows the server's own pages with `?tv=1&client=tv` (the desktop app sees the Bigscreen session),
   so it is a TV device. Check on the real shell: open You, then Libraries, Live transcoding and Channels and tuners;
   each should be the card with the address, a QR code and Back focused, and Back (Escape from the remote) should
   return. Open Controllers and My game settings: both should work fully with a pad.
8. The desktop app started with `--tv` anywhere else sends `client=desktop`: a computer in TV mode. Check on Linux,
   Windows and macOS that the same screens say "Leave TV mode to change this." with no QR code, that Leave TV mode
   opens the same page in the normal layout with Back to TV mode, and that started without `--tv` every editor opens.

## What a relay allows (issue 65, WittyMediaServer #476)

Written 2026-11-18 on the Windows PC. The connection library now reports, through a relay that carries whole
connections, what the relay allows: `relayKbps`, `relayMaxHeight` and `relayAllows`. The apps say it beside
"through a relay", for example **Peer to peer · through a relay · 4 Mbit/s, 720p**.

Checked on the PC: the desktop's `test/p2p.test.js`, and WittyKit's `PeerConnectTests` built and run with Swift 6.1 on
Linux. **Not checked:** the Android unit test (`PeerRulesTest.whatARelayAllowsIsSaidAndNothingElseFromIt`) and any app
on a real device.

- [ ] `cd android && ./gradlew testDebugUnitTest --tests '*PeerRulesTest*'` passes
- [ ] `swift test --filter PeerConnectTests` passes in `apple/WittyKit` with Xcode
- [ ] With the server and a WittyRelay from the server's `docs/REMOTE.md`, "Try it yourself", an iPhone or Apple TV
      simulator on a network that blocks direct connections shows the line with the limits

## Peer to peer, hardened (0.8.2)

Written 2026-11-23 on the Windows PC. An invite link's server name is shown without control characters or the
invisible ones that turn text around (`PeerConnect.shownName`, the same on Android and the desktop). The server now
also ends a device's sign-ins when it is taken off the list.

Checked on the PC: WittyKit built and its `Peer` tests (30) run with Swift 6.1 on Linux; the desktop's
`test/p2p.test.js`; the desktop's real peer-to-peer harness (`test/app/p2p-real.js`, home, away, invite and the new
`revoked` phase) under xvfb on Linux against a local server. **Not checked:** anything in Xcode or on a device.

- [ ] `swift test --filter PeerInviteTests` passes in `apple/WittyKit` with Xcode
- [ ] On an iPhone and an Apple TV simulator, an invite whose name has a right-to-left override (`n=Home%E2%80%AEtxt.exe`)
      shows "Hometxt.exe" before connecting
- [ ] On an iPhone reaching the server from away: take the iPhone off the list in Settings, Remote Access on the server.
      The app stops getting answers at once, and after "Change server" and back it asks for a sign-in again (the old
      one was ended with the device)
- [ ] `./desktop/test/app/p2p-real.js --phase=revoked` passes on macOS after `--phase=home` and `--phase=away` (see the
      file for what to set)
