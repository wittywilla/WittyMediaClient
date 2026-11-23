<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- Copyright (C) 2026 WittyWilla and contributors -->
# WittyMediaServer 0.8.1-alpha in the apps

What WittyMediaServer 0.8.1-alpha added (its CHANGELOG, `docs/TV-MODE.md`, `docs/UI-PLATFORMS.md` and the PRs
merged into `v0.8.1-alpha`), and where each app stands with it. Written 2026-11-19 on the Windows PC.

How to read it:

- **Free**: the app shows the server's own web page there, so the feature came with the server. The desktop app
  (Windows, macOS, Linux, FreeBSD, Plasma Bigscreen) is the website in a window, so almost everything is free there.
  Android phones and tablets show the server's page for the owner's tools (see the feature map in
  [APP-DESIGN.md](APP-DESIGN.md#feature-map)). Apple TV has no web engine: everything there is native or a card.
- **Done here**: changed in this branch (`clients-081-parity`) on Windows. *Ran* says it was seen running against a
  0.8.1 server; *tests* that only unit tests ran.
- **Written, Mac**: Swift written on Windows. WittyKit's part was compiled and tested with Swift 6.1 on Linux; the
  apps themselves are only compiled, by CI's macOS runner. Never run. Checks are in
  [MAC-FOLLOW-UPS.md](../MAC-FOLLOW-UPS.md#081-alpha-what-the-mac-must-do).
- **Gap**: not done anywhere yet. **Not needed**: the feature is the server's own, or a computer's.

The server used: built from WittyMediaServer `origin/v0.8.1-alpha` (`bd10cb6e`), fresh data, a few read-only folders
of the owner's media with metadata writing off; on Windows at `127.0.0.1:19555` for the desktop app, and the same
commit built for Linux inside WSL on its port 19555 for the Android emulators. Pictures:
`D:\projects-0.8.0\_status\082-fixes\clients\` (desktop, desktop-tv, android-phone, android-tv).

## The table

| 0.8.1 feature (server PR) | Windows, Linux, FreeBSD desktop | macOS desktop | Android phone and tablet | Android TV | iPhone and iPad | Apple TV |
|---|---|---|---|---|---|---|
| **TV mode levels**: editors are a card that sends a TV to a computer, with what's set now and a QR code (#475) | Free; `--tv` sends `client=desktop`, so a computer in TV mode gets **Leave TV mode** (client #64). Ran, `test:real --tv` 11 of 11 | Free, same code. Mac to look | Not needed (phones aren't TVs) | Done here: a server page the app draws itself (Libraries, the menu's pages…) now keeps to the table too; before, You → Libraries opened a form with folder paths to type. Ran | Not needed | Written, Mac: the table read from the catalogue (`TvLevels.swift`), the card says the server's words with what's set now (`EditorOnComputerPage`), and SDUI routes to an editor go to it |
| **Skip parts from a `.wittyinfo`**: previews, a named part, a scene after the credits, "mark only", a file that skips by itself (#466, #467) | Free (the web player) | Free | Done here: `segments`, preview and named parts with their own button ("Skip dream sequence"), credits stop at a scene after them, marked-only parts have no button, **What the video's own file says to skip** (on). Tests; the settings page ran | Done here, same code. Tests | Written, Mac (WittyKit tested on Linux) | Written, Mac (same code) |
| `.wittyinfo` / `.wittyaudio` editor | Free | Free | Free (the server's page) | Not needed: desktop only, the card | Free (the server's page) | Not needed: the card |
| **Video quality menu**: resolution and bitrate, `quality` in `/playback` (#439) | Free | Free | Gap: the native player has no quality menu | Gap | Gap | Gap |
| Video player scene pictures, menus, phone layout (#462, #391, #415) | Free | Free | Not needed: the native player has its own | Not needed | Not needed | Not needed |
| **Karaoke Mix**: Voice, Background Music and Track (#418) | Free | Free | Done here, ran: three sliders on every version, the voice's own slider and Sing on the bar, Mix for all three | Done here, ran: the same, every slider reached with the remote and moved 5% at a time | Written, Mac (WittyKit tested on Linux). The quick version can't take the music below the voice there (a mixer node's volume can't be negative) | Written, Mac (same code) |
| Karaoke's old voice control removed (#412) | Free | Free | Done here, ran: on a server that makes the parts, only the Mix (and "Preparing karaoke…" while it's made) | Done here | Already so | Already so |
| Karaoke Voice settings panel, album art beside the words, hiding the bar's parts (#425, #413, #418) | Free | Free | Gap: not in the native karaoke | Gap | Voice settings written, Mac (client #82); the rest a gap | Voice settings written, Mac (client #82) |
| Demucs one-press install, DirectML (#436, #478) | Not needed (server) | Not needed | Not needed | Not needed | Not needed | Not needed |
| **Setup revamp** and **where settings and data are kept** (#508, #473, #386, #379-#383, #434) | Free: setup is the server's page, done in a browser. The client app only shows "This server isn't set up yet" | Free. The Mac **server** app's own side is in WittyMediaServer's MAC-FOLLOW-UPS.md | Not needed: the app shows the setup address and its QR code | Not needed | Not needed | Not needed |
| **Theme scrim and contrast** (#444, #411) | Free; the client's own theme data was regenerated from 0.8.1's themes (client `0dbb225`) | Free | Already done (client `21aea44`, `HeroScrim.kt`) | Already done | Gap, Mac: the Apple apps draw their own fades and don't read `tv.heroScrim` (see the Mac list) | Gap, Mac |
| **Music navigation**, the music frame (#432, #464, #468, #496) | Free | Free | Not needed: native music pages, unchanged. The server's fixes to what's listed (no duplicate album) come through | Not needed | Not needed | Not needed |
| **Live TV check-up**: recordings survive a drop, errors in words, `tvg-shift` (#474) | Free | Free | Free: the server's words are shown as they come | Free | Free | Free |
| **Peer to peer**: plain answers, relay limits, your own WittyRelay (#477) | Done in client #64 and #66 | Done (#66), Mac to look | Done (#66) | Done (#66) | Written in #66, Mac | Written in #66, Mac |
| **The server's language**: 26 languages, right to left (#389, #511) | Free: the server's pages | Free | Gap: the native screens are English | Gap | Gap | Gap |
| WittyPlay's controller screen and game settings | Free | Free | Free (the server's page) | Free: `full` in the table, so it opens | Free | Gap (Apple TV has no web engine): the card |
| Web page top, page column, pill bar (#435, #409, #410, #417, #422, #440) | Free | Free | Not needed: native shell | Not needed | Not needed | Not needed |

## The UI changes after client #67 (2026-11-22)

What landed in WittyMediaServer `v0.8.1-alpha` after #67, or is on its way there, and what the Apple apps and the
macOS desktop app have of it. The macOS desktop app is the website in a window, so every change to the web page is
there with the server. Its own parts (the title bar, the menu bar, TV mode's menu, the data folder) were checked
against each change, and none needed changing. iPhone, iPad and Apple TV draw everything themselves. **Ported** means
done on branch `apple-081-ui` (WittyMediaClient #82): written on Windows, WittyKit tested on Linux, the apps compiled
by CI's macOS runner, **never run**. The checks are in the top section of [MAC-FOLLOW-UPS.md](../MAC-FOLLOW-UPS.md).
Reference pictures: `docs/mac-081/ui/` here, and `D:\projects-0.8.0\_status\082-fixes\` on the PC.

| Change (server PR) | macOS desktop | iPhone and iPad | Apple TV |
|---|---|---|---|
| Mini player: square art (#523, #522) | Free | Already so (the art is a fixed square, 48 and 64) | Already so |
| Mini player: Lyrics, Karaoke and Visualizer in a **More** menu (#523) | Free | **Ported**: the iPad's wide bar (900 across and up) has More with the three. The phone's bar never had them | Not needed: Now Playing has its own buttons |
| Mini player see-through on a phone (#551, item 3) | Free once the web fix lands | **Ported**: a solid backing under a glass theme's panel colour | Not needed: TV's mini player is opaque |
| Settings scroll bar, Activity → History's filter, Demucs row padding (#523) | Free | Not needed: native lists, no web settings | Not needed |
| Placeholder art's title at every size (#523, #514) | Free | Already so: the title shows on any card over 72 wide (`PlaceholderArt`) | Already so |
| **Karaoke**: clean first screen, voice off by default, **Guide voice**, **Mix** panel, **Voice settings** with nine presets and Advanced, visualizer styles, idle hiding (#524, #518, #519) | Free | **Ported**, all of it. The Mix is a side panel on an iPad and a sheet on a phone. Advanced's sliders show on an iPad; a phone gets the website's "bigger screen" note. The sound comes from new units in `StemPlayer` | **Ported**: Guide voice, Mix and Voice settings on the karaoke bar, presets with the remote. Advanced says to use a computer (`karaoke.voice-advanced` is desktop-only) |
| Karaoke: Controls (hiding parts of the bar), Album art beside the words, Fill the screen (#524, #413) | Free | Gap: not ported. Apple has no per-part hiding or side cover yet | Not needed |
| Lyrics: one Follow along / Read switch; the cover left or right (#524, #520, #515) | Free | Already so: one `LyricsModeToggle`. The cover's side is the app's own layout | Already so |
| Scan progress names a module's step (#525, WittyPlay #88) | Free | Not needed: the apps only say "Scanning…" | Not needed |
| WittyPlay: desktop rescale, hover never selecting, core picker, in-game menu fitting (WittyPlay #89, #90, #92, #93; #547) | Free | Not needed: the app has its own game player and pages, with no pointer hover, and the core is the server's | Not needed |
| Module entries placed in More stay in More (#538) | Free | **Ported**: of the entries placed in More, the strip of sections lists only the libraries and Collections | Left as is: Apple TV's top menu puts every entry in its scrolling row by design. A Mac check asks whether Server folders should move |
| **Backdrops fade into the page on every side** (#545) | Free | **Ported**: a title's header and the detail picture fade by a mask (`HeroFade`), not by painting the page colour over them, and an iPad's sides fade too. The phone's swiping billboard keeps its scrim for the words over the picture | **Ported**: Home's billboard, the title header and Browse's hero |
| The theme's scrim, `tv.heroScrim`, read by the Apple apps (#444) | Free | Gap, Mac (step 8 of the 2026-11-19 list, still open) | Gap, Mac |
| Setup: saved keys, the server's address with a QR code, converter wording (#546, open) | Free | Not needed: setup is the server's page, in a browser | Not needed |
| HDHomeRun search and messages (WittyTuner #24) | Free | Not needed: WittyTuner's settings are its web pages | Not needed |
| Live TV's channel banner shows for 3 s (#557, open) | Free | Not needed: no live TV banner on iPhone | Done in client #71 (`TvChannel.swift`, open) |
| Readability tokens (#531, open) | Free once merged | **Waits**: CI checks `shared/data/themes.json` against the server's branch, so it's regenerated once #531 merges | Same |
| Phone shell: top strip, activity button over Help, action row cut off (#551; ui-audit-081, no PR yet) | Not needed (desktop) | Already so: the strip lists only what's behind Menu, and the action row is one row with ⋯. There's no activity button on Apple | Not needed |
| Setup's form and Games step (#550), the too-old-module message (ui-audit-081) | Free | Not needed: setup and module installs are the server's pages | Not needed |
| TV album page with disc groups; no keyboard hints in TV mode (tv-album-081, no PR yet) | Free | Already so: an album groups its songs by disc | Gap: Apple TV's album page waits for tv-album-081's design. Keyboard hints: Apple TV shows none (`ShellShortcuts.swift` isn't built for tvOS), and its only remote hints are essential ones (the game player's controls, "Play/Pause twice for live") |
| WittyTV guide with the shortcuts toggle; a profile picker like the desktop's | Free | Who's watching? as one centred column: **owned by android-test-081** (client #84) | Guide (preview at most 440 wide, rows snapped, a Shortcuts chip in place of the dock, no letter badges, Help entry, legal on one line) and Who's watching?: **owned by android-test-081**. Android TV is done in client #84, and its `MAC-FOLLOW-UPS.md` section "WittyTV guide and Who's watching? on Apple TV" has the Apple steps. Not ported here |
| Video player quality and audio menu, the connect screen's safe margin, the see-through first-run chooser, remote digits keeping the legend's glyphs (android-test-081, PRs to come) | Free | Owned by android-test-081: check its PRs for an Apple section | Same |
| TV settings | Free | Owned by tv-settings-parity | Owned by tv-settings-parity |

## Also found while running it

- **Android phone, first-run "Choose a layout"** (after signing in to a server with no look chosen): Home's library strip
  shows through above the page, and a card of Home's below it, at the very top and bottom edges
  (`android-phone/03-after-code.png`). Not fixed here.
- **Desktop `test:real --tv`** still expected the TV menu's old order; **Manage servers** now sits between Change
  server and Quit. The test is fixed, and its last step no longer fails when Windows still holds the temporary folder.
- **The server doesn't name `.wittyinfo` or the quality menu as features** in `/capabilities`, so an app can't tell a
  0.8.1 server from 0.8.0 for them. The Android and Apple apps show the new skip rows wherever `skip-markers` is (an
  older server just has nothing to skip). A feature name for each belongs in a server PR.

## What changed in this branch

- `android/…/player/SkipRules.kt`, `net/MediaExtras.kt`, `player/ExtrasPrefs.kt`, `player/SkipTracker.kt`,
  `ui/YouPlaying.kt`: the new skip parts. `SkipRulesTest.kt`.
- `android/…/player/KaraokeRules.kt`, `player/KaraokeStems.kt`, `ui/Karaoke.kt`: the three-slider Mix. `KaraokeRulesTest.kt`.
- `android/…/ui/App.kt`: `Nav.go` sends a desktop-only server page to the card on a TV.
- `apple/WittyKit/Sources/WittyKit/MediaSkips.swift`, `KaraokeStems.swift`, `TvLevels.swift` (new),
  `SDUI/SDUICatalog.swift`, and tests `MediaSkipsTests`, `KaraokeStemsTests`, `TvLevelsTests` (new).
- `apple/App/MediaPages.swift`, `MediaSkips.swift`, `KaraokeStemsViews.swift`, `ModulePages.swift`, `Shell.swift`,
  `SDUI/SDUIActions.swift`: the screens for the above. **Never run.**
- `shared/data/strings.en.json`: `skipPreviews`, `skipCustom`, `skipFileAuto`.
- `desktop/test/app/real-server.js`: the TV menu's order, and the temporary folder.

## What ran, and how

| | Where | Result |
|---|---|---|
| Desktop `npm test` | Windows 11 | 202 passed, 3 skipped |
| Desktop `test:real`, desktop and `--tv` | Windows 11, Electron 45.2.1, against the 0.8.1 server | 8 of 8, and 11 of 11 |
| Android unit tests, and the debug build | WSL, Gradle 9.8.2 | 658 tests, 0 failures, 6 skipped |
| Android phone emulator (Android 16) | WSL | Found the server on the network, signed in with a code, Home, You → Playing on this device, karaoke's Mix on the quick version |
| Android TV emulator (Android 16, 1080p) | WSL | Signed in with a code, Home, You → Libraries as the card, karaoke's Mix with the remote alone |
| WittyKit `swift test` | Swift 6.1 on Linux (Docker, WSL) | 737 tests; the new ones pass. Apple's own frameworks (UserDefaults suites, SwiftUI) aren't all there on Linux, so CI's macOS runner is the real check |
| The iPhone, iPad and Apple TV apps | CI's macOS runner (`build.yml`, `apple`) | Compiled and archived. Never run |
