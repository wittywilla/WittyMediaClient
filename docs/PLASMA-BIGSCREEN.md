# Plasma Bigscreen and the Linux desktop

> **Status: a plan, 2026-11-05.** Nothing on this page has been built or run for it. What has run is in
> [PLATFORMS.md](PLATFORMS.md#freebsd-plasma-bigscreen-and-linux). The owner builds and tests this on their own Windows
> and Linux PCs, with the steps below.

How KDE's Plasma Bigscreen gets **every feature** of WittyMediaServer and the **TV interface** the Apple TV and
Android TV apps have ([APP-DESIGN.md](APP-DESIGN.md#on-a-tv)), in two phases:

1. **Phase 1: the desktop app opens the server's TV mode.** Full parity at once, from what's already built.
2. **Phase 2: a native Qt/QML Kirigami app.** The best a Linux TV can do: libmpv playback with VA-API, HDR and
   passthrough, CEC remotes, SDL controllers for WittyPlay, the 8-letter TV code, themes through the translation layer.

- [Where this stands](#where-this-stands)
- [Phase 1: the desktop app and the server's TV mode](#phase-1-the-desktop-app-and-the-servers-tv-mode)
- [Phase 2: a native Kirigami app](#phase-2-a-native-kirigami-app)
- [Input](#input)
- [Packaging](#packaging)
- [The Linux desktop](#the-linux-desktop)
- [Building and testing on your PCs](#building-and-testing-on-your-pcs)
- [Parity with Apple TV](#parity-with-apple-tv)

## Where this stands

- The desktop app (`desktop/`, Electron 45) already opens as a TV app inside a Bigscreen session: whole screen, no title
  bar, `?tv=1` on the server's address ([PORTING.md](PORTING.md#plasma-bigscreen), `desktop/tv.js`). It ran in Plasma
  Bigscreen 6.8.2 on Fedora 44 in a virtual machine, never on a TV, with a real remote or with hardware decoding.
- Until now `?tv=1` meant the server's **Big screen mode**: the desktop layout with bigger words. The server's
  **TV mode** replaces it (WittyMediaServer `docs/plans/TV-MODE.md`, pull request
  [#297](https://github.com/wittywilla/WittyMediaServer/pull/297)): the website laid out and driven as Apple TV is, with
  Home, Libraries, Games, Live TV and Search along the top and You at the right, every control a pill, concentric focus
  rings, LB and RB for tabs, and Back that goes from a page to the bar, from the bar to Home, and out. The same `?tv=1`
  turns it on, so **the app gets the TV interface with no change of its own** once the server has that pull request.

## Phase 1: the desktop app and the server's TV mode

**What it gives:** every page of the server, in the TV layout, on Bigscreen, the day the server is updated. That's
more than Apple TV has today, since the owner's settings are real pages here rather than a QR card.

**What the app still needs, small and in this order:**

| # | Change | Where | Why |
|---|---|---|---|
| 1 | **Sign in with a code shown on the TV**: `POST /pair/start {device, platform: "Plasma Bigscreen"}`, show `ABCD-EFGH` big with a QR card of `approveUrl`, poll `POST /pair/poll` every `intervalSec` | `shared/connect/` (TV only), `desktop/main.js` | Apple TV and Android TV have it (APP-DESIGN, Signing in, 8). The desktop app has only the six digits typed on the TV (`/pair/redeem`). `platform` is a free label of up to 20 characters on the server |
| 2 | **Back, checked against TV mode**: in TV mode the page answers Escape itself (to the bar, to Home), and leaves an Escape untouched only on Home's bar. `preload.js`'s fallback then opens the TV menu, as now. Keep its copy of `OWN_BACK` in step with the server's `web/src/tv.ts` | `desktop/preload.js` | So Back never leaves the app by accident and the menu still comes up from Home |
| 3 | **Hardware video decoding**: Chromium's VA-API switches on Linux (`--enable-features=AcceleratedVideoDecodeLinuxGL,VaapiVideoDecoder` and `--ignore-gpu-blocklist` where the driver needs it), only in a TV session, with a way out (`--no-hw-decode`) | `desktop/tv.js` `switches()` | A small Bigscreen box can't decode 4K HEVC in software. Chromium's flags change between versions: check them on each Electron update |
| 4 | **Words:** `tenFootAddress()` and its comment say "big screen mode"; rename to what it now opens | `desktop/tv.js` and its test | Plain wording |

**What Phase 1 can't do,** and why Phase 2 exists: Chromium on Linux plays HDR as SDR, sends no Dolby or DTS to an
amplifier (no passthrough), decodes what its own codecs can, and has no CEC of its own (Bigscreen's input handler turns CEC
into key presses, which works for moving and Back but not for the TV's own power or input switching).

## Phase 2: a native Kirigami app

Qt 6, QML and **Kirigami**, KDE's own toolkit, which Bigscreen and its apps are built with. It sits beside the other
native apps, in `linux/`, and shares with them what they share: `shared/data` (wording, themes, test cases, button
meanings) and `shared/fixtures` (real server answers). The server decides everything two clients would have to agree on,
as for Apple and Android ([PORTING.md](PORTING.md#the-decision)).

| Part | Built with | Notes |
|---|---|---|
| Screens | QML, Kirigami, and a small `WittyStyle` QML module for the TV look | Laid out exactly as APP-DESIGN's On a TV, measured in TV units (one is a point at 1920×1080, so a 4K screen doubles them). Focus with QML's `KeyNavigation` and `FocusScope`, a 4-wide concentric ring in `text` and 1.06, every control a pill |
| Talking to the server | C++, `QNetworkAccessManager`, `QJsonDocument` | `/api/v1`, the token in the `Authorization` header. Errors and retries as `PlaybackRules` does on Apple and Android, with the same tests from `shared/data` |
| Finding servers | C++: mDNS with KDNSSD (or Avahi), then the server's UDP question `WMS-DISCOVER/1` on 9797 | The same order as `desktop/discover.js` |
| Video and sound | **libmpv**, through KDE's `MpvQt` (the library Haruna uses) | See below |
| WittyPlay | FFmpeg's `libavcodec` with VA-API for H.264, PipeWire for PCM, **SDL3** for controllers | See below |
| Sign-in kept | A file in the app's config folder, readable only by its user | As the desktop app does on a TV: KWallet's first-run wizard would open over the app, and a TV has no keyboard to get through it |

**Playback with libmpv.** The server's own playback API (`POST /items/{id}/playback`) says whether to play the file
directly or through the server's HLS; mpv plays both.

- **Hardware decoding:** `hwdec=vaapi` (Intel and AMD) or `hwdec=nvdec` (NVIDIA), with `hwdec=auto-safe` as the default.
- **HDR:** `vo=gpu-next` with `target-colorspace-hint=yes`, so KWin's HDR (Plasma 6's colour management protocol) gets
  HDR10 and HLG as they are; on an SDR screen, mpv's tone mapping.
- **Passthrough:** `audio-spdif=ac3,eac3,dts,dts-hd,truehd` to the HDMI output through PipeWire or ALSA, as a setting
  on You → this device, because only the owner knows what their amplifier takes.
- **Discs:** the server's DVD and Blu-ray menus are its own (the website's `player/DvdPlayer.tsx`); Phase 2 builds the
  same player around mpv, with the disc remote on every disc type, as the other TV apps will.
- The player's controls copy the website's (APP-DESIGN, Playback and the media player): left and right seek 10
  seconds, OK brings up the controls, Back leaves.

**Remotes over HDMI-CEC.** Bigscreen's `plasma-bigscreen-inputhandler` already reads CEC (through libcec) and turns
buttons into keys, so the app handles ordinary Qt key events (see [Input](#input)). A PC's graphics card has no CEC
wiring: a TV PC needs a USB-CEC adapter (Pulse-Eight's), or a board with CEC (a Raspberry Pi's HDMI has it).

**Controllers with SDL3.** SDL's game controller database names every common pad's buttons the same way, Xbox,
PlayStation and Nintendo alike, with rumble. Two uses:

- **Moving around:** as on the website, A chooses, B goes back, LB and RB change tab, Start opens a screen's options.
  Bigscreen's input handler stops turning a pad into keys when another program opens it (seen in PLATFORMS.md), so
  the app reads the pad itself once it has it open, and nothing is pressed twice.
- **WittyPlay:** the server runs every game and streams it (WittyMediaServer `docs/GAMING-API.md`). The app asks
  `GET /games/modes?client=native`, uses `ws-h264` (H.264 Annex B over the WebSocket, PCM sound) with `ws-jpeg` as the
  fallback, sends controller states up the same socket in the server's format, and stops with `DELETE /play/{sid}`.
  Its game menu is the one every device has (Resume, Press Start, Press Select, Save, Load, Reset, Quit). WebRTC can come
  later, through `libwebrtc` or GStreamer's `webrtcbin`, as it's the lowest latency.

**Pairing with the 8-letter TV code**, as Apple TV: `POST /pair/start`, the code in Display monospaced with a QR card
of `approveUrl`, polled until `approved`, `denied` or `expired` (WittyMediaServer `docs/CLIENT-API.md`). The six digits
(`/pair/redeem`) stay as the other way.

**Themes through the translation layer.** Every server theme (`shared/data/themes.json`, then `GET /themes` for the
owner's and the person's own) is translated to the same roles as on Apple and Android (APP-DESIGN, Themes,
Translation), and given to QML as one `Palette` singleton. Kirigami's own colours (`Kirigami.Theme`) are set from it,
so its controls match. Theme choice is per server on the device, as in the other apps.

**When to start Phase 2:** once Phase 1 has run on a real TV with a real remote. If Phase 1's picture, sound and
remote are good enough for the owner, Phase 2 is for HDR, passthrough and the lowest game latency, and can wait.

## Input

What each thing sends, and what it does. Rows marked **web** are the server's TV mode (Phase 1), **native** Phase 2.

| Source | Button | Arrives as | Does |
|---|---|---|---|
| HDMI-CEC, through the input handler | Up, Down, Left, Right, Select | Arrows, Enter | Move, choose |
| | Back, Exit | Escape (`Qt::Key_Escape`) | Back: a page to the bar, the bar to Home, Home's bar to the app's menu |
| | Play, Pause, Stop, Rewind, Fast forward, Previous, Next | Media keys (`Qt::Key_MediaPlay`…) | In the player, as on every TV app |
| | Red, Green, Yellow, Blue | F1 to F4 where the handler maps them | The guide's coloured keys, the disc remote's |
| | Home | Taken by the shell | Bigscreen's home |
| Game controller, while the input handler has it | D-pad or left stick, A, B, Select | Arrows, Enter, Escape, `BrowserBack` | Move, choose, Back |
| Game controller, once the app has opened it | Everything | **web:** the Gamepad API (`web/src/ui/gamepad.ts` on the server). **native:** SDL3 | Move, choose, Back; LB and RB change tab; Start opens options; in a game, everything goes to the game |
| | Guide | Taken by the shell | Bigscreen's home overlay |
| Keyboard | Arrows, Enter, Escape, Backspace, Page Up and Down | The same keys | As a remote; Page Up and Down change tab |
| Mouse, touch | | | Still work: every control is a real button; screens opened from a tab have a round Back for a pointer |

## Packaging

- **Phase 1** is the desktop app's packages as they are: `.deb`, `.rpm` and `.pacman` (`npm run package:linux`), which
  add the launcher entry Bigscreen lists. An AppImage works but adds no entry.
- **Phase 2:** CMake with KDE's Extra CMake Modules, a desktop file (`Categories=AudioVideo;Video;Player;TV;`, the
  same `wittymediaclient` icon), and packages for the same three: CPack or each distribution's own spec, PKGBUILD and
  `debian/` folder. Its dependencies: Qt 6 (Base, Declarative, Network), Kirigami, KDNSSD, MpvQt and libmpv, FFmpeg's
  libraries, SDL3, PipeWire.
- **Flatpak, later**, for both: on Flathub against KDE's runtime (`org.kde.Platform`), with the network, PipeWire, the
  GPU and `--device=all` for controllers. Not before the packages above have run on a real TV ([PORTING.md](PORTING.md#plasma-bigscreen)).

## The Linux desktop

Outside Bigscreen, Linux keeps the **desktop app as it is**: the server's website in a window, its desktop layout,
`.deb`, `.rpm`, `.pacman` and AppImage, on any desktop (KDE Plasma, GNOME and others). `wittymediaclient --tv` gives the
TV mode on any Linux connected to a TV; `--no-tv` turns it off inside Bigscreen. The Phase 2 app is for TVs: Kirigami
would let it run in a window on Plasma's desktop too, but the desktop app stays the one for a desk.

## Building and testing on your PCs

Everything here runs on your own machines. Use a server on your network, and a test account rather than your own.

### On the Linux PC (Phase 1)

1. **Install a Bigscreen session.** On Fedora 44 with KDE: `sudo dnf install plasma-bigscreen plasma-nm kscreen`
   (without the last two it stops at an error screen). On Arch: `sudo pacman -S plasma-bigscreen`. Log out, and choose
   **Plasma Bigscreen** on the sign-in screen.
2. **Get the code and Node.js 24:** `git clone https://github.com/wittywilla/WittyMediaClient`, then install Node.js 24
   from your distribution or nodejs.org.
3. **Run the checks:** `cd WittyMediaClient/desktop && npm ci && npm test`.
4. **Run it from the code, as a TV:** `npm start -- --tv`. Choose your server, sign in, and you should see the server's
   TV mode (once the server has pull request #297): the bar of pills along the top, You at the right.
5. **Make and install the package:** `npm run package:linux`, then `sudo dnf install ./dist/wittymediaclient-*-linux-amd64.rpm`
   (or `sudo apt install ./dist/…deb`, `sudo pacman -U ./dist/…pacman`). In the Bigscreen session it's in the launcher;
   open it from there, with no flags.
6. **Against your server, automatically:** `WMC_SERVER=http://<server>:9797 WMC_USER=<test user> WMC_PASSWORD=… npm run test:real -- --tv`.
7. **Remote:** with a USB-CEC adapter on the TV's HDMI, `cec-client -l` lists it; the arrows, OK and Back on the TV's
   own remote should move and choose in the app. Back from a page should reach the bar, then Home, then the app's menu.
8. **Controller:** plug one in; `evtest` shows it. Move, choose, B for Back, LB and RB for tabs, Start on Home for
   Customize. Then play a game from Games, and leave it with the game menu.
9. **Hardware decoding:** `vainfo` says what the GPU can decode. Play a 4K HEVC file and watch the processor in
   `htop`: well under one core means the GPU decodes (after Phase 1's change 3).

### On the Windows PC (Phase 1)

Windows can't run Bigscreen, but it runs the same app and the same TV mode:

1. Install Node.js 24 and Git for Windows. In PowerShell: `git clone https://github.com/wittywilla/WittyMediaClient`,
   `cd WittyMediaClient\desktop`, `npm ci`, `npm test`.
2. `npm start -- --tv` opens the app as a TV. Or open the server in Edge or Chrome as `http://<server>:9797/?tv=1` and
   press F11.
3. With an Xbox or PlayStation controller: everything in step 8 above. With a keyboard: arrows, Enter, Escape, Page Up
   and Page Down.
4. `npm run package:win` makes the installer; a shortcut with `--tv` after the program's name opens it as a TV.

### Phase 2, when it exists

On the Linux PC: `sudo dnf install cmake extra-cmake-modules qt6-qtbase-devel qt6-qtdeclarative-devel kf6-kirigami-devel kf6-kdnssd-devel mpvqt-devel mpv-libs-devel ffmpeg-free-devel SDL3-devel pipewire-devel`
(names differ a little on other distributions), then `cmake -B build -S linux && cmake --build build && ./build/bin/wittymediaclient-tv`.
Its tests: `ctest --test-dir build`. Check HDR with an HDR10 file on an HDR TV with HDR turned on in Plasma's display
settings, and passthrough with a Dolby Digital file and an amplifier that shows the format it receives.

## Parity with Apple TV

Tick each one on a real TV. "Web" is Phase 1 (the server's TV mode in the desktop app), "native" Phase 2.

| Feature | Apple TV | Bigscreen, Phase 1 | Bigscreen, Phase 2 | Checked |
|---|---|---|---|---|
| Choose your server, from the network or an address | Native | The app's own connect screen | Native | ☐ |
| This isn't the server you used before (security code) | Native | Connect screen | Native | ☐ |
| Sign in with a code shown on the TV (8 letters) | Native | To add (change 1) | Native | ☐ |
| Who's watching, password, two-step | Native | Web, TV layout | Native | ☐ |
| Top bar: Home, Libraries, Games, Live TV, Search; You at the right | Native | Web | Native | ☐ |
| Home: hero and rows, long titles whole | Native | Web | Native | ☐ |
| Libraries as tiles, and each library | Native | Web | Native | ☐ |
| Movies, shows, seasons, episodes, item pages | Native | Web | Native | ☐ |
| Video playback, resume, next episode, skip intro, tracks, subtitles | Native | Web (software decoding until change 3) | Native, libmpv | ☐ |
| Hardware decoding | System | Change 3 | VA-API | ☐ |
| HDR10, HLG | System | No: SDR | Yes | ☐ |
| Dolby and DTS passthrough | System | No | Yes | ☐ |
| DVD and Blu-ray menus, the disc remote on every disc type | To build | Web | Native | ☐ |
| Music, audiobooks, podcasts | Native | Web | Native | ☐ |
| Photos | Native viewer | Web | Native | ☐ |
| Books, comics, PDFs | To build | Web | Web page, then native | ☐ |
| Live TV guide in every WittyTV look, recordings | Native | Web | Native | ☐ |
| Games: couch library, a shelf per games library | Native | Web | Native | ☐ |
| Playing a game with a controller | Native, streamed | Web, streamed | Native, streamed | ☐ |
| Search with a keyboard on the screen | System keyboard | Web, on-screen keys | Native | ☐ |
| You in two columns; theme on this device | Native | Web | Native | ☐ |
| The owner's settings | QR card | Web, the real pages | Web pages | ☐ |
| Every server theme | Native | Web | Native, translated | ☐ |
| Focus: concentric ring, 1.06, pills; first focus on the main action, and back where it was | System focus engine | Web | Native | ☐ |
| Back: page to bar to Home to out | Native | Web, with change 2 | Native | ☐ |
| LB and RB change tab; Start opens options | Not in APP-DESIGN yet | Web | Native | ☐ |
| A TV remote over HDMI-CEC | Siri Remote | Input handler | Input handler | ☐ |
