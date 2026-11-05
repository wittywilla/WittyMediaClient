# WittyPlay on Android

How the server's games play in the Android app on phones, tablets and Android TV. The server runs every game and streams
it; the app shows the picture, plays the sound and sends the controls (WittyMediaServer `docs/GAMING-API.md`). No emulator
and no game file is ever on the device. The design is [How the apps look](APP-DESIGN.md), "Games everywhere"; the
protocol choices are the Apple player's (`docs/WITTYPLAY-STREAMING.md` on the Apple TV branch), made the same way here.

## The connection

| Mode | On Android | When |
|---|---|---|
| `ws-h264` | H.264 Annex B from the WebSocket into `MediaCodec`, asynchronous, onto a `SurfaceView`. `KEY_LOW_LATENCY` where the decoder has it, realtime priority, and each frame released to the screen the moment it's decoded. More than three frames waiting means the stream is behind: they're dropped and the decoder waits for the next keyframe, asking for one (`0xF7`) | First, whenever the server offers it |
| `ws-jpeg` | One JPEG a frame, decoded into a reused bitmap and drawn on the same surface, sharp unless `display.scaling` is smooth | No picture 12 seconds after connecting, or the server's `hello` says `jpeg` |
| `webrtc` | Not used: it needs libwebrtc in the app | Later, for playing away from home |

Sound is PCM at the console's own rate into a low-latency `AudioTrack`, written without ever waiting; what's queued is
kept within `audio.latency` (50, 90 or 160 ms) by dropping, so it stays with the picture. `audio.volume` and `audio.mute`
apply. The sign-in goes in the WebSocket upgrade's `Authorization` header, by the app's own HTTP client, never in an address.

A dropped connection is made again within the server's minute; past it, or if the server has stopped the game, the player
offers Resume from the automatic save. Leaving the app lets go of every control, pauses the game when
`emulation.pauseHidden` says so, and closes the connection; coming back reconnects and unpauses. Save and quit is
`DELETE /play/{sid}` and waits for the save; leaving the player any other way still stops the game on the server.

## Controls

- **Gamepads** arrive as key and joystick events, read into the W3C standard layout by position, which is how Android names
  them too (a Nintendo pad's A, on the right, is `BUTTON_B`). The right stick is `Z`/`RZ`, or `RX`/`RY` on pads without
  them; triggers are `LTRIGGER`/`RTRIGGER` or `BRAKE`/`GAS`; a hat is the D-pad. The mapping is the console's
  `defaults.gamepad`, then the layout saved under the pad's name, then the account's profile for `vendor:product` from
  `/game-profiles/resolve`; its dead zone, press point, stick-as-D-pad, turbo and no-rumble apply here. Start and Select
  together open the menu; the person's Select shortcuts (`hotkeys.pad.*`) fast-forward, rewind, quick save and so on.
- **Players**: each pad takes the next free player, 1 to 4, when it's plugged in, and keeps it; the game menu can move
  one to another player. Unplugging lets go of everything it held.
- **Rumble** goes to the pad on that player through `VibratorManager` (two motors where it has them), or its `Vibrator`.
- **A keyboard** plays as player 1 by the console's keyboard layout; Escape opens the menu, and the person's key shortcuts work.
- **A TV remote** is for the menus (APP-DESIGN): Back or OK opens the game menu, which has Press Start and Press Select.
- **Touch**, on phones and tablets with no controller in use: the account's layout for this device and orientation from
  `/consoles/{console}/controls`, drawn and read with the website player's own sums. On a console with a touch screen
  (the DS), a finger that misses every control is the stylus on the picture. Upright, the picture sits in the top half.

## The screens

| Part | Files |
|---|---|
| Library in couch mode: covers, Continue playing, consoles, shelves, every game with the website's sorts, a console's page, search | `games/GameLibrary.kt` |
| A game's page: Play or Resume (by `states.resume`), Start over, favourite, default settings, Pick up where you left off, save states, other versions, how it plays, controls, and the server's own reason where it can't play | `games/GamePage.kt` |
| The player, loading steps, problems, the game menu | `games/GamePlayer.kt`, `games/GameTouchControls.kt` |
| A session, the stream, sound, input | `games/GamePlay.kt`, `games/GameMedia.kt`, `games/GameInput.kt` |
| Data, routes, and the logic the tests cover | `games/GameData.kt`, `games/GamesApi.kt`, `games/GamePad.kt`, `games/GameTouch.kt`, `games/GameStream.kt` |
| Into the app | `ui/GamesRoute.kt`, and one line each in `Nav.open`, AppRoot and `MainActivity` |

## Not yet

WebRTC; the `display.*` effects beyond shape, whole multiples and rotation (scanlines, masks, bezels); arranging the touch
controls on the device (a touch layout belongs to the device that saved it, so until then this device uses the console's
default; the save route is in `GamesApi.saveTouchLayout`); game settings, cheats and patches (the website's).
