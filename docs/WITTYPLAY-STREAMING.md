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

## Controllers on Apple TV: what passes through

| What | Apple TV | Carried by the protocol |
|---|---|---|
| MFi, Xbox, DualShock 4, DualSense, Switch Pro, Joy-Cons (a pair, or one on its side), and anything else GameController knows | Read through GameController. A Joy-Con on its own is a small pad: its stick is the D-pad | Yes |
| Every button, the D-pad, both sticks at full range, analog triggers | Read in the W3C standard layout the profiles are written in; triggers go out as 0 to 255 as well as their button bits | Yes: 16 buttons, two i16 sticks, two u8 triggers |
| Players | Each controller gets the next free player, keeps it while connected, and a pad that goes lets go of everything at once. The Siri Remote plays as player 1 alongside a pad. Four, or up to eight where the second stream says the game takes more and the session's devices for those further ports take a controller: a Super Nintendo's fifth through its multitap, but not an NES's fifth, the Famicom's expansion port. A console that needed an adapter for players 3 and 4 needs it plugged in: on an NES, a controller that joins as player 3 or 4 plugs a gamepad into that port when it's on "Auto", which turns the Four Score on. On a Super Nintendo, the Multitap goes into player 2's port from the game menu's Controllers page. On the second stream, the server is told which players this device holds | Ports 0 to 3 on the first stream; 0 to 7 on the second, with `seats`; and `device` actions |
| The account's profiles | `/game-profiles/resolve` per controller, console and game; dead zone, press point, stick-as-D-pad, turbo and no rumble applied on the device | Yes |
| Rumble | Core Haptics on the player's pad: the strong motor on the left handle and the weak on the right where the pad has two, each held for as long as the event says and replaced by the next; 0 stops it | Yes: `rumble` with `motor` (or the first stream's `effect`), `strength` and, on the second stream, `ms` |
| DualSense and DualShock 4 touchpad, for a console with a touch screen (DS, 3DS) | The touchpad is the touch screen: where the finger is, and a click to press. A press is sent again every 250 ms, and a release three times | Yes: the 6-byte pointer message. One point only |
| Light bar | Set to the player's colour (blue, red, green, pink). A core's own lights arrive as `led` events; libretro has no colour light bar, so the pad keeps its player's colour | `led` on the second stream |
| Motion (gyro and accelerometer) | Read from the pad's sensors, switched on only for the players the game asks about, and sent as often as it asks, up to 60 a second: gravity and movement in g, turning in radians a second, as the protocol's 1/4096 g and 1/16 degree a second | On the second stream: `0xE1`, while `motion` events (or the stream's `motionOn`) want it. No core reads motion yet |
| Adaptive triggers, the DualSense's speaker and microphone | Not used | **No** |
| Home | Opens the game menu where tvOS lets an app have it, and tvOS is asked not to act on a controller's buttons while a game plays | Not needed |
| Options (Start) | Start for the game; held for a second it opens the game menu. Start and Select together open it at once, as on the website | Not needed |
| Siri Remote | Its D-pad, select and Play/Pause by the console's `defaults.remote`; Back opens the game menu; it steers the menu | Yes |
| A keyboard | By the console's `defaults.keyboard`; Escape opens the menu | Yes |

**What the second stream added** (WittyMediaServer#296, WittyPlay#37), and this app uses: motion (`0xE1`), lights (`led`),
the two rumble motors with how long to hold them, and up to eight players. It also has several touches at once (`0xFE`);
this app sends the one stylus a DS or 3DS needs with the single-touch message, which still works.

**What's still missing:**

- **Which adapter a third player needs.** The session lists each port's devices, but not that an
  NES's players 3 and 4 need a gamepad in their own ports while a Super Nintendo's need a Multitap
  in player 2's. The server could plug in what four players need when the app says how many are
  holding controllers, or say it per console, instead of each app knowing each core.

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

## The Apple client

One player for Apple TV, iPhone, iPad and Apple Vision Pro: the same engine, input and model on all
of them, with `#if os(...)` only where a device differs (the Siri Remote, focus, touch).
`GamePlayerView(gameId:)` is the screen to show for a server game on any of them. The library, the
game's page and the menu's look wait for the new WittyPlay design; on iPhone and iPad the library
and game's page are the server's page until then.

| Part | How | Files |
|---|---|---|
| The library (Apple TV) | Couch mode's look at TV size: covers at the top, one at the front and the rest turned away on a shiny floor, the page tinted by the front cover's colour; Continue playing with each save's picture; Consoles; Recently added, Favourites, Most played, series and genre shelves; every game with the website's sorts; a console's own page | `apple/App/GamesViews.swift` |
| A game's page (Apple TV) | Its box, Play or Resume (by `states.resume`), Start over, favourite, start with default settings, "Pick up where you left off", about and facts, save states (play from one, hold to delete), how it plays, its controls | `GamesViews.swift` |
| The connection | A `GameTransport` (WittyKit), chosen by the session's mode. Where the server has its second stream (a mode marked `"stream": 2`), WebRTC comes first: libwebrtc (LiveKit's build, 144.7559.15) with one `POST /play/{sid}/stream` carrying the hello and the offer, receive-only picture and sound, and data channels `input` (unordered, never resent) and `events`. It decodes the picture in hardware and the player draws it through its own Metal path, so display settings still apply; it plays the sound itself, for playback only, so the microphone is never touched. If it hasn't connected within 5 seconds, or shown a picture within 8, the second stream's WebSocket takes over: `/play/{sid}/stream`, opening with the device's hello (its id, name, screen, the players it holds, `emulation.latency`), frames with timestamps, `seats`, `stream`, refusals and endings with their codes, and how late frames arrive (`delayMs`) twice a second so a slow network doesn't fill with video. The first stream's WebSocket (`ws-h264`, `ws-jpeg`) stays behind it, and is all a server without the second stream offers. Sound is Opus, decoded with AVAudioConverter, or PCM where a device can't. On Apple TV, where the person lets apps match the TV to what they show, the TV switches to the game's rate (50 Hz for a PAL game) and the server is told the new rate, so it paces the game to it; it goes back on leaving. Apple TV needs tvOS 17 for this | `apple/WittyKit/Sources/WittyKit/GameTransport.swift`, `GameStreamV2.swift` |
| The picture | `ws-h264` into VideoToolbox, drawn with Metal the moment a frame is decoded; `ws-jpeg` if no picture comes in 12 seconds; a new connection after 4 seconds with none | `apple/App/GameMachinery.swift` |
| The person's picture settings | `display.*`, applied on the device as the server asks: sharp, pixel or smooth scaling, whole multiples, shape, crop, rotation, scanlines, a curved screen, a phosphor mask, a vignette, an LCD grid, brightness, contrast, saturation and gamma in one Metal shader; a bezel colour or image with its inset. Not yet: glow, blend, flicker | `GameMachinery.swift` |
| Sound | PCM at the console's own rate into AVAudioEngine, kept within `audio.latency`; volume and mute | `GameMachinery.swift` |
| Controllers, remote, keyboard | As above | `apple/App/GameInput.swift`, `apple/WittyKit/Sources/WittyKit/GamePad.swift` |
| Touch controls (iPhone, iPad) | Below | `apple/App/GameTouch.swift`, `apple/WittyKit/Sources/WittyKit/TouchControls.swift` |
| The pause menu | Resume, Save state (slots, with pictures), Load state, Quick save and load (`states.quickSlot`), Press Start, Press Select, Change disc, Controllers (who's on which player, their profile, and what the console's emulator lets each player plug in), Reset, Save and quit, asking first where `states.confirm` says. Opened by the remote's Back, Home, Options held, or Start and Select together | `apple/App/GamePlayer.swift` |
| Models and API | | `apple/WittyKit/Sources/WittyKit/Games.swift`, `GamesAPI.swift`, `GameStream.swift` |

**Themes:** every colour on these screens is the theme's, the server's or the one chosen on the
device, so they follow every theme and WittyTV look as the rest of the app does.

**Consoles:** every console the server plays, since the TV only shows its stream. The Nintendo DS and
3DS need a DualSense or DualShock 4 for their touch screen, whose touchpad becomes it; without one,
games that need the stylus are for a browser or a phone, and the game's page says so.

### Touch controls

With no controller connected, iPhone and iPad draw the account's touch layout over the game, as the
website's WittyPlay player does, so a layout arranged on the website looks and plays the same here.

- **The layout** is the server's: `GET /consoles/{console}/controls?device=<this device>` has the
  console's `controls`, `defaults.touch` for portrait and landscape, and `saved.touch`, what was saved
  for this device id, which replaces those controls' placements. A placement is a centre as fractions
  of the screen and a size as a fraction of its shorter side. There are no touch profiles.
- **Drawn** as the website draws them: tinted glass by the console's controller, a rounded plus for the
  D-pad with arrows that light, round face buttons (PlayStation marks, Nintendo 64 C arrows), shoulder
  buttons rounder at the bottom, pills for Start and Select, a stick with a cap that follows the finger.
- **Played** as the website plays them: any number of fingers; sliding off one button onto another;
  hit circles a little larger than the buttons; an eight-way D-pad with a small dead middle; a stick
  that a finger takes only by landing on it, with a 0.12 radial dead zone; C buttons push the right
  stick. A short tap for each new press. Start and Select together open the menu, as on a pad.
- **Upright,** the picture moves into the top 52% and the controls sit below it; sideways the picture
  has the whole screen and the controls sit over it.
- **DS and 3DS:** a finger that lands on no control is the stylus until it lifts, and with a controller
  connected any finger on the picture is. Its position is taken from where the picture was really
  drawn, with any turn undone, so it lands where the finger is.
- **Hiding them:** a button beside the menu's, and Show or Hide touch controls in the menu. The choice
  stays on this device. They hide on their own while a controller is connected, and come back when it goes.
- **Vision Pro** plays with a controller by default; the touch controls can be turned on from the menu.

**Checked on an iPhone simulator** (iPhone 18 Pro), with debug builds' `-WittyPlayTouchPreview snes` and `nds`. These show
the real overlay with the server's SNES layout and log each press, since no game could start with the media shares
unmounted:

- **Upright:** the picture's area took the top 52%, with L and R, the D-pad, the face buttons as a diamond, and Select and
  Start below it, as the website places them. Tapping each logged a, b, y, x, l, r, select and start. The D-pad gave up,
  right, down, left and up+right for a diagonal. One finger sliding from Y to A logged y, then a.
- **Sideways:** the landscape layout covered the whole screen, and A and the D-pad still pressed in their new places.
- **DS:** a tap on the picture was the stylus at that point, and a tap on A was A.

Not checked: a real game's picture under the controls, the tap felt on a phone, and an iPad.

## Which consoles play from this Mac's server

Tried from Apple TV's own decoding code against the local server, with one game from each console that has games there. Retail games were used for testing only.

| Console | Core | Result |
|---|---|---|
| NES | FCEUmm | Plays: 512×448 H.264, sound, input, a save to a slot and the automatic save on quitting |
| Super Nintendo | Mesen-S | Plays |
| Game Boy | Gambatte | Plays |
| Nintendo DS | melonDS | Plays: both screens as one 512×768 picture. Its touch screen takes a DualSense or DualShock 4 touchpad |
| PlayStation | PCSX ReARMed | **Doesn't start**: a multi-disc game unpacks (660 MB), then the server reports "the game took too long to load". No BIOS file was given; the core can run without one, but this game didn't |
| Nintendo 64, PSP, PlayStation 2 | Mupen64Plus-Next, PPSSPP, Play! | **Can't play on a Mac server**: these cores draw with a graphics card, and the server says hardware-rendered games run on Windows and Linux. PlayStation 2 also needs a BIOS file that wasn't given |
| Nintendo 3DS | Azahar | **Can't play**: the only game is an encrypted file, which the server refuses and never decrypts |

Two things on the server side came out of this. `GET /games/{id}/check` says ready for the graphics-card consoles on a Mac, which can't run them. And three of those failing in a row took WittyPlay out of use for every game until it was put back.

## Controllers, checked on NES, Super Nintendo and DS

Against the local server, two ways.

**On the Apple TV simulator,** in the app: the NES and Super Nintendo 240p Test Suites and a DS game
(Resume) played. The D-pad, A and B moved through the suites' menus and opened and closed their tests.
The game menu opened, paused the game, and its Controllers page listed the four players' ports with
what each console's emulator offers. When the same account started a game elsewhere, the TV said the
game had stopped and been saved. The simulator has no real controller, so its keyboard stood in.

**Button by button,** from WittyKit's own encoding through the same socket code as the app: each
button held while the server took the game's picture (`GET /play/{id}/screenshot`), against the
suites' controller tests.

| Console | What lit up |
|---|---|
| Super Nintendo | B, Y, Select, Start, Up, Down, Left, Right, A, X, L and R, each on player 1 alone and only its own label; player 2's L, Up and A on player 2 alone |
| NES | B, Select, Start, Up, Down, Left, Right and A on controller 1 alone (Y, which an NES lacks, nothing); player 2 on controller 2. Players 3 and 4 only once a gamepad was plugged into their ports, then each on its own controller |
| Nintendo DS | Touching the middle of the lower screen moved past a title that waits for a touch, which it didn't do untouched for as long; Start moved on from the title |

Still to try with real hardware: rumble, the light bar, the touchpad itself (its pointer was sent as
the app sends it), Home and Options, and analog sticks and triggers in a game that shows them.

## The second stream, against a stand-in

Before a server with the second stream was running, the Apple player's transport, decoder and input ran on the Mac
against the stand-in WittyPlay's `wittyplay-probe run` makes from the stream's own branch (on 127.0.0.1 only):

| Game | What came, and what it did |
|---|---|
| The probe's test core | The hello was taken and the stream described itself (WebSocket, H.264, PCM, 512×448, four players), paced to the 60 Hz screen the hello said. 911 frames in 15 seconds, every one decoded by VideoToolbox with no keyframe asked for; 2.8 MB of PCM. A held: the strong motor at full for 300 ms, renewed every 200 ms, then stopped. Select: light 0 on, then off. The core asked for player 1's accelerometer and gyroscope at 60 a second, and two seconds of motion went in without a refusal |
| An NES game (FCEUmm) | 834 frames, every one decoded; sound at 47,920 Hz, because the game's 60.0998 Hz was paced to the screen's 60 and its sound resampled to match |
| The same, asking for Opus | 962 Opus packets, every one decoded to 10 ms of 48 kHz stereo by the app's decoder |
| The test core over WebRTC | The app's WebRTC transport: the stream said `webrtc`, H.264 and Opus; the first picture 0.64 seconds after connecting, then 926 in 16 seconds, every one handed to the Metal path as BGRA. A and Select over the `input` channel brought the rumble and the light back on `events`, as over the WebSocket |

What the stand-in can't show: sign-in, `/api/play/{sid}`, `modes` and the server's error codes, which the server's own
tests cover; nor a TV switching its refresh rate, which needs a real Apple TV. It's also what's left to run on a device.

## Testing it without a server that plays

Before the Mac fix was running, the player was first proved through a test stand-in on
127.0.0.1:9798 (not in this repository) that ran WittyPlay's own runner and core and spoke the
protocol above. With the fix, everything was run against the real server: see the pull request.
