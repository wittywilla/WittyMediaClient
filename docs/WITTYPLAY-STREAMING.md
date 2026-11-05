# WittyPlay streaming: the server plays, the TV shows

How games play on a TV that can't run them: the server runs the emulator, sends the picture and sound
down as a low-latency stream, and the app sends controller states back up. This is the design, and
what the Apple TV app does with it.

## The decision

**The engine already exists, and it's WittyPlay.** WittyPlay never runs a game in a browser or on a
device. Its own design says: "Every game runs on the server and is streamed. The device you hold only
decodes the picture, plays the sound and sends your presses" (WittyMediaServer `docs/GAMING.md`). It
has a protocol written for apps (`docs/GAMING-API.md`, "What a TV app must build itself"), with a mode
made for a client that has no WebRTC.

So this needs no new server engine. Apple TV is a native client of that protocol, built only from
Apple's frameworks. The one server change it needed was on the Mac: WittyPlay's runner was refused
its own sandbox inside the helper's ([wittywilla/WittyMediaServer#276](https://github.com/wittywilla/WittyMediaServer/pull/276)).
No emulator ships in the app.

## Where the emulator runs

| Option | What it is | Verdict |
|---|---|---|
| **WittyPlay's runner** | Each game runs as a separate, sandboxed runner process on the server, with a libretro core and no window. Frames go over a pipe to WittyPlay, which encodes them with FFmpeg, on the graphics card when it can, and streams them. Measured (`docs/GAMING.md`, headless, NVENC): finished frame to screen 9 ms on the NES, 13 on the SNES, 22 on the N64, 14 on the PS2. A press reaches the screen in 11 to 49 ms | **Use this.** It exists, its saves, profiles, settings and sessions are the website's own, and its sandbox and GPL boundary (a separate process over a pipe) are already reviewed |
| A browser on the server running the web player | There's no emulator in the web player to run: it's a stream client. This would mean bringing in WebAssembly cores (whose SNES and Genesis licences don't allow it), a headless Chromium per player, and capturing its canvas and sound, then encoding them again | No. More memory and delay for each player, weaker sandboxing, and a second way of saving |
| A Moonlight-compatible host (Sunshine) on the server | Sunshine shares a whole display; each player would need their own virtual display with RetroArch in it, paired by PIN, with nothing joining it to the account's saves and profiles | No, for the server's own games. It stays the way to play a real PC (WittyRigs, below) |

## Transport

What each end already has decided this. On the server: WittyPlay's three modes. On Apple TV:
VideoToolbox, which decodes H.264 in hardware, and `URLSessionWebSocketTask`. tvOS has no WebRTC
of its own.

| Mode | Picture, sound, input | Apple TV | Delay | Verdict |
|---|---|---|---|---|
| **`ws-h264`** | H.264 Annex B frames, each keyframe with its parameter sets; PCM; 13-byte states on the same WebSocket | VideoToolbox in hardware, AVAudioEngine, nothing to add | A frame as soon as it's whole, no buffering. TCP, so a lost packet holds up what follows: fine at home, worse on a lossy link | **Use now** |
| `ws-jpeg` | A JPEG a frame | ImageIO | More bits, no inter-frame delay | **Fallback**, when no picture comes in 12 seconds or the server has no H.264 encoder |
| `webrtc` | H.264 or VP8 over RTP with no jitter buffer, Opus, data channels | Needs Google's libwebrtc (BSD) built for tvOS: a large binary to keep up to date | Best on a lossy network: late frames are dropped, not waited for | **Later**, for playing away from home |
| HLS or fMP4 | Segments for AVPlayer | Built in | A second or more, even low-latency HLS tuned down | No: too slow to play with |
| Moonlight / GameStream | Sunshine's protocol | No Moonlight client for Apple has a URL scheme, and its GPL code can't go in this app | Excellent | Only for real PCs, as now |

**Encoding** is the server's choice of what works on it: VideoToolbox on a Mac, NVENC, VAAPI or
Quick Sync elsewhere, and libx264 or OpenH264 in software. The local test server has libx264,
OpenH264, libvpx and VideoToolbox. A retro console's picture, doubled, is about 512×448 at 60 frames
a second, which a CPU encodes easily; consoles drawn on a graphics card (N64, Dreamcast, PS2, the
PlayStation's HW cores) need one on the server.

## The input protocol

As documented in `docs/GAMING-API.md`, "Controller states", and nothing new:

- **A state** is 13 bytes, little-endian: the player (0 to 3), 16 RetroPad buttons as bits, both
  sticks as signed 16-bit, and both triggers as 0 to 255. Sent whenever it changes, and again every
  250 ms so a lost one corrects itself. Everything is let go when a menu opens or the app leaves.
- **Mapping** is data from the server: the console's `defaults.gamepad` (W3C standard numbers, laid
  out by position), then the account's profile for this controller, console and game from
  `GET /game-profiles/resolve`, where `null` takes a button away. Its options are applied on the
  device: dead zone (a circle), press point, the left stick steering the D-pad, turbo, no rumble.
  tvOS doesn't give apps a pad's USB numbers, so common pads are named by kind (a DualSense is
  `054c:0ce6`) to find the profiles made for them in a browser, and others by `id:<name>`.
- **The Siri Remote** presses what the console's `defaults.remote` says: the clickpad's edge is the
  D-pad, its middle `Enter`, Play/Pause `MediaPlayPause`. **Back opens the game menu** and is never
  a game button. The menu has Press Start and Press Select, for what a remote can't reach.
- **Shortcuts** as on the website: Start and Select together always open the menu; with the
  person's shortcut button held (`hotkeys.padModifier`), their `hotkeys.pad.*` buttons fast-forward,
  slow down, rewind, quick save, quick load, pause or step a frame. The shortcut's button isn't seen
  by the game while it's held.
- **Rumble** comes down as an event and plays through Core Haptics on that player's pad.

## Saves and states

They stay on the server, where the website keeps them. The TV never holds one.

- `POST /games/{id}/play` with `resume: true` starts from slot 0, the automatic save written when a
  game stops, wherever it was played. So the website and the TV resume each other.
- Saving and loading are actions on the session: slots 1 to 99 to save; 0, 100 (before the last
  load) and 101 (before starting over) can also be loaded. `GET /games/{id}/saves` lists them, with
  pictures.
- Quitting is `DELETE /play/{sid}`, which answers once the automatic save and the battery save are
  written. A session nobody is connected to is saved and stopped after 60 seconds.

## Sessions and security

- **Sign-in:** the account's bearer token, in the `Authorization` header of every request and of
  the WebSocket's upgrade. Never in an address.
- **Ownership:** a session belongs to the account that started it, and is 404 to anyone else. One
  game at a time per account: starting another, on any device, saves and ends the first. One game,
  up to four players on the device playing it (ports 0 to 3), and at most 8 viewers.
- **Profiles:** what Kids and Guest profiles may do is the server's to enforce.

## Limits

- **No graphics card on the server:** every 2D console still plays, encoded in software. Consoles
  that need one say so on the game's page, from `GET /games/{id}/check`.
- **Others watching films at the same time:** the server runs two games at once by default
  (`gamingMaxSessions`), two on the graphics card, and answers 503 past that. Runners run at a lower
  priority than transcoding on Linux and macOS.
- **At home and away:** the WebSocket works anywhere HTTP does, through the server's own address
  and HTTPS, at the cost of the network's round trip. WebRTC needs the server's UDP port reachable
  (Settings, Consoles & cores), and is the better choice away from home, which is why it's the next
  thing to add on Apple TV.

## WittyRigs and game PCs

Unchanged. A game in a `console: rig` library plays on a real PC through Sunshine and Moonlight
(`apple/WittyKit/Sources/WittyKit/Rigs.swift`). The server answers 409 with `rig: true` if one is
started with `POST /games/{id}/play`.

## The Apple TV client

| Part | How | Files |
|---|---|---|
| The library | Couch mode's look at TV size: covers at the top, one at the front and the rest turned away on a shiny floor, the page tinted by the front cover's colour; Continue playing with each save's picture; Consoles; Recently added, Favourites, Most played, series and genre shelves; every game with the website's sorts; a console's own page | `apple/App/GamesViews.swift` |
| A game's page | Its box, Play or Resume (by `states.resume`), Start over, favourite, start with default settings, "Pick up where you left off", about and facts, save states (play from one, hold to delete), how it plays, its controls | `GamesViews.swift` |
| The picture | `ws-h264` into VideoToolbox, drawn with Metal the moment a frame is decoded; `ws-jpeg` if no picture comes in 12 seconds; a new connection after 4 seconds with none | `apple/App/GameMachinery.swift` |
| The person's picture settings | `display.*`, applied on the device as the server asks: sharp, pixel or smooth scaling, whole multiples, shape, crop, rotation, scanlines, a curved screen, a phosphor mask, a vignette, an LCD grid, brightness, contrast, saturation and gamma in one Metal shader; a bezel colour or image with its inset. Not yet: glow, blend, flicker | `GameMachinery.swift` |
| Sound | PCM at the console's own rate into AVAudioEngine, kept within `audio.latency`; volume and mute | `GameMachinery.swift` |
| Controllers, remote, keyboard | As above | `apple/App/GameInput.swift`, `apple/WittyKit/Sources/WittyKit/GamePad.swift` |
| The pause menu | Resume, Save state (slots, with pictures), Load state, Quick save and load (`states.quickSlot`), Press Start, Press Select, Change disc, Controllers (who's on which player, their profile, and what the console's emulator lets each player plug in), Reset, Save and quit, asking first where `states.confirm` says | `apple/App/GamePlayer.swift` |
| Models and API | | `apple/WittyKit/Sources/WittyKit/Games.swift`, `GamesAPI.swift`, `GameStream.swift` |

**Themes:** every colour on these screens is the theme's, the server's or the one chosen on the
device, so they follow every theme and WittyTV look as the rest of the app does.

**Consoles:** every console the server plays, since the TV only shows its stream. The Nintendo DS and
3DS only partly: their touch screen can't be reached from an Apple TV, so games that need the
stylus are for a browser or a phone, and the game's page says so.

## Testing it without a server that plays

Until a server with the Mac fix is running, the Apple TV player was proved through a test stand-in
on 127.0.0.1:9798 (not in this repository): it passes every request to the real server except
starting, streaming, actions and stopping, which it does by running WittyPlay's own runner and core,
encoding with the server's own FFmpeg and speaking the protocol above. Saves made through it stay in
the stand-in. See the pull request for what ran.
