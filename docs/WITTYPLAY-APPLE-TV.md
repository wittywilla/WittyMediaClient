# WittyPlay on Apple TV

How the server's games play on Apple TV, which consoles that covers, and what the emulators' licences mean for this app.

## How WittyPlay works, and so how Apple TV plays it

**WittyPlay runs every game on the server and streams it.** The server's own design says so: "Every game runs on the
server and is streamed. The device you hold only decodes the picture, plays the sound and sends your presses: no game
runs in a browser, a phone or a TV, and no copy of a game is sent to one" (WittyMediaServer's `docs/GAMING.md`). The
website's player isn't an emulator in the page. It's a WebRTC or WebSocket client, and no route of the API hands a game's
file to a client (`internal/server/api_games*.go`). Libretro cores built to run in a page were considered and set aside
by the server's design in 2026-11, for delay, for one way of saving, and for licences.

So libretro cores built for tvOS, as RetroArch and Provenance ship them, would be a second WittyPlay that the server
doesn't have. It would need a copy of every game on the TV, and a way to save that the website can't read. The native
way to play on Apple TV is the one the server documents for TV apps (`docs/GAMING-API.md`, "What a TV app must build
itself"), built with Apple's own frameworks:

| Part | How | Files |
|---|---|---|
| The library and a game's page | SwiftUI, laid out as the website's couch mode (`/big`) at TV size: covers at the top with one at the front and the rest turned away on a shiny floor, the page tinted by the front cover's colour, then Continue playing, Consoles, the shelves and every game with its sorts. A game's page has its box, Play or Resume, Start over, favourite, "Pick up where you left off", its details, its save states, how it plays and its controls | `apple/App/GamesViews.swift` |
| The picture | The `ws-h264` mode: H.264 Annex B frames over a WebSocket, decoded by VideoToolbox, drawn with Metal. `ws-jpeg` if no picture comes in 12 seconds. A frame is drawn the moment it's decoded | `apple/App/GameMachinery.swift` |
| The person's picture settings | The `display.*` group applied on the device, as the server asks: sharp, pixel or smooth scaling, whole multiples, shape (as the game says, 4:3, 16:9, square pixels, fill, custom), crop, rotation, scanlines, a curved screen, a phosphor mask, a vignette, an LCD grid, brightness, contrast, saturation and gamma, in one Metal shader. The bezel: black, a colour, or the person's own image, with its inset | `GameMachinery.swift` |
| Sound | PCM at whatever rate the console makes, into AVAudioEngine, kept within the person's `audio.latency` by leaving a little out when behind. `audio.volume` and `audio.mute` | `GameMachinery.swift` |
| Controllers | GameController: MFi, Xbox and PlayStation pads, read in the W3C standard layout that the server's mappings are written in. Up to four players, a controller keeping its player while it stays connected. The console's defaults, with the account's controller profile for that controller, console and game over them (`/game-profiles/resolve`), and the profile's dead zone, press point, stick-as-D-pad and turbo. Rumble through Core Haptics, unless the profile turns it off | `apple/App/GameInput.swift`, `apple/WittyKit/Sources/WittyKit/GamePad.swift` |
| The Siri Remote and keyboards | The remote presses what the console's `defaults.remote` says: the clickpad's edge is the D-pad, its middle is A, Play/Pause is B. A keyboard follows `defaults.keyboard`. The remote's Back button opens the game menu and isn't a game button | `GameInput.swift`, `apple/App/GamePlayer.swift` |
| Shortcuts | As on the website: Start and Select together always open the menu; with the person's shortcut button held (Select unless they changed it), their `hotkeys.pad.*` buttons fast-forward, slow down, rewind, quick save, quick load, pause or step a frame | `GamePad.swift` |
| The game menu | Resume, Save state (a slot, with each slot's picture), Load state (every save, including the automatic one and "before the last load"), Quick save and Quick load to the person's `states.quickSlot`, Press Start, Press Select, Change disc, Reset and Save and quit, asking first where `states.confirm` says to. While it's open the game is paused and nothing reaches it | `GamePlayer.swift` |
| Saves | The server's. Play resumes slot 0 when the person's `states.resume` says so, Start over doesn't, and a save state on the game's page starts from that slot. Quitting is `DELETE /play/{sid}`, which writes the automatic save and the battery save before it answers, so the game's page shows them on return. Leaving any other way still stops and saves | `GamePlayer.swift` |
| Games on someone's own PC | Unchanged: a game in a `console: rig` library still goes to `ItemView` and plays through Moonlight (`apple/WittyKit/Sources/WittyKit/Rigs.swift`) | `BrowseViews.swift`, `Shell.swift` |

**Why not WebRTC.** The server lists WebRTC first, and on tvOS it means Google's libwebrtc, which Apple doesn't ship.
It's BSD-licensed, so it could come into the app, but it's a large binary to keep up to date. On a home network the
WebSocket with H.264 does the same job, and needs only what tvOS has. Away from home the WebSocket works anywhere HTTP
does. WebRTC would win on a lossy network, as it drops a late frame rather than waiting for it, and could come later.

**Themes.** Every colour on these screens comes from the theme in use, the server's or the one chosen on this
device, so the games screens follow every theme and every WittyTV look the way the rest of the app does. The cover's
tint is made deep on a dark theme and pale on a light one, as on the website.

## Which consoles

Every console the server can play, because the TV only shows what the server runs. What a console needs is the
server's business: a core installed by its administrator, a BIOS for some, a graphics card for some. The game's page
says which, in the server's words. Today's list, from `GET /games/consoles`:

| Console | Cores the server offers (licence) | Needs the server's graphics card | On Apple TV |
|---|---|---|---|
| NES | FCEUmm (GPL-2.0), Nestopia UE (GPL-2.0), Mesen (GPL-3.0) | | Yes |
| Super Nintendo | Beetle Supafaust (GPL-2.0+), bsnes 2014 Performance (GPL-3.0), Mesen-S (GPL-3.0) | | Yes |
| Game Boy, Game Boy Color | Gambatte (GPL-2.0), SameBoy (MIT), mGBA (MPL-2.0) | | Yes |
| Game Boy Advance | mGBA (MPL-2.0), VBA Next (GPL-2.0) | | Yes |
| Mega Drive / Genesis | BlastEm (GPL-3.0), ClownMDEmu (AGPL-3.0) | | Yes |
| Master System, Game Gear | Gearsystem (GPL-3.0), SMS Plus GX (GPL-2.0) | | Yes |
| PC Engine / TurboGrafx-16 | Beetle PCE Fast (GPL-2.0) | | Yes |
| Atari 2600, 7800, Lynx | Stella 2014, Stella (GPL-2.0), ProSystem (GPL-2.0), Handy (Zlib) | | Yes |
| WonderSwan, Neo Geo Pocket, Virtual Boy | Beetle WonderSwan, Beetle NeoPop, Beetle VB (GPL-2.0) | | Yes |
| PlayStation | PCSX ReARMed, Beetle PSX (GPL-2.0), SwanStation (GPL-3.0), Beetle PSX HW (GPL-2.0) | For the HW cores | Yes, with sticks and rumble |
| Nintendo 64 | Mupen64Plus-Next, ParaLLEl N64 (GPL-2.0) | Yes | Yes, with the stick and C buttons on the right stick |
| Dreamcast | Flycast (GPL-2.0) | Yes | Yes |
| PlayStation 2 | LRPS2 (GPL-3.0), Play! (MIT) | Yes | Yes |
| PSP | PPSSPP (GPL-2.0) | | Yes |
| Nintendo DS, 3DS | melonDS (GPL-3.0), DeSmuME (GPL-2.0); Azahar (GPL-2.0+), Panda3DS (GPL-3.0) | | **Partly.** These have a touch screen, and Apple TV has no way to point at the picture: the remote's touch surface is a D-pad here. Games that only use buttons play; games that need the stylus are for a browser or a phone |
| An administrator's own consoles (`custom-…`) | Their own cores | As set up | Yes: a whole RetroPad |

## Licences

**This app ships no emulator.** It holds only its own code and Apple's system frameworks (VideoToolbox, Metal,
AVFoundation, GameController, Core Haptics, SwiftUI), so NOTICE has nothing to add. The cores' licences above are the
server's to meet: its administrator installs them, and WittyPlay runs each one in a separate runner process that the
Apache-licensed server only talks to over a pipe, which is how the server keeps GPL code out of its own binaries
(`internal/server/api_games.go`, `gameRunner`).

**App Store and sideloading are the same for this app.** Nothing in it is under the GPL, so the App Store's terms
don't meet a copyleft licence anywhere, and the app stays Apache-2.0 either way.

**What it would mean to put cores in the app instead**, which is why that's the wrong way for this project even apart
from the server's design:

- **GPL-2.0-only cores can't be combined with this app at all.** The app is Apache-2.0, and the FSF holds Apache-2.0
  incompatible with GPLv2: its patent and indemnity terms are "further restrictions" GPLv2 doesn't allow. That's FCEUmm,
  Nestopia, Gambatte, PCSX ReARMed, the Beetle cores, Mupen64Plus, Flycast and PPSSPP, most of the list.
- **GPL-3.0 cores could be combined, but the whole app would then be GPL-3.0.** Apache-2.0 code may go into a GPLv3
  work, not the other way round. Every build would have to come with its source.
- **The App Store and the GPL don't mix without the authors' permission.** Apple's usage rules (a limited number of
  devices, no redistribution) are restrictions the GPL forbids adding, which is why VLC was taken off the App Store in
  2011. Emulator apps that do ship GPL code on the App Store rest on their copyright holders' consent, which this
  project doesn't have for anyone's cores. So an App Store build could carry only permissively licensed cores:
  SameBoy (MIT), mGBA (MPL-2.0, whose file-level copyleft only asks for its own files' source), Handy (Zlib) and Play!
  (MIT). That's Game Boy, Game Boy Advance, the Lynx and, on paper, the PlayStation 2. Everything else could only be
  sideloaded, and then only by an app relicensed GPL-3.0, and still never with the GPL-2.0-only cores.
- **AGPL-3.0 (ClownMDEmu)** adds that anyone using it over a network can ask for the source.
- **tvOS also gets in the way.** An app can't load code that isn't signed inside its bundle, and can't use a JIT, so a
  core would have to be built into the app and the faster recompiling cores (Dreamcast, PSP, PlayStation 2, 3DS) would run
  their slow interpreters.

Streaming from the server avoids all of it, and plays every console the server plays, at the server's speed.

## What was checked

See the pull request that brought this in for exactly what ran. In short:

- WittyKit's games tests (models from the server's real answers, controller states, profiles over defaults, shortcuts,
  the stream's messages, Annex B, the picture's shape) pass with the rest.
- The Apple TV and iPhone apps build.
- The protocol was checked from a Mac against the local server: playing, the WebSocket with the sign-in in its header,
  H.264 with its parameter sets before each keyframe, PCM, a save to a slot, and the automatic save on stopping.
- On the local server WittyPlay's own runner couldn't start any game: every start answered "The emulator crashed",
  for every core tried, while the same runner, core and game played when started by hand, even under the module's
  sandbox profile. The module's README says its macOS build has never been run on a real Mac. That's for WittyPlay to fix;
  until then the Apple TV player was run on the simulator through a test stand-in that runs that same runner and core,
  encodes with the server's own ffmpeg, and speaks the documented protocol.
