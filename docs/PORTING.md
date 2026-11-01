# Porting to TVs

How WittyMediaClient reaches Apple TV and Android TV, what is done, and what is left. The aim is that a TV
port is a matter of building and testing, not a redesign. [PLATFORMS.md](PLATFORMS.md) says how far each claim
has been checked; this page says what the plan is.

**Where this stands:** neither TV app has ever run. Android's code is type-checked and its logic and network
calls are tested, but no APK has been built since this work began. Apple's SwiftUI has never been compiled.

## The decision

**tvOS has no web view.** Apple doesn't offer WebKit to tvOS apps at all, so nothing based on the server's web
interface can run on an Apple TV. Whatever else is shared, the screens on an Apple TV have to be native.

So each family gets a native app, and what they share is data and rules rather than code:

| | Apple TV, iPhone, iPad, Mac | Android TV, Google TV, Fire TV, phones, tablets |
|---|---|---|
| Screens | SwiftUI | Jetpack Compose |
| Player | AVPlayer, with the system's controls on Apple TV | Media3 (ExoPlayer), with our controls |
| API, identity, discovery | `apple/WittyKit` | `android/.../net` |
| Shared between the two | `shared/data`: themes, wording, test cases, button meanings. `shared/fixtures`: real server answers | the same |

The server decides everything two clients would have to agree on: `docs/CLIENT-API.md` in its repository. A rule
written in only one client is a bug waiting to happen, so rules that must live in a client (retries, the playback
clock) are written the same way in both, with the same names and the same tests: `PlaybackRules.swift` and
`PlaybackRules.kt`.

Kotlin Multiplatform and a shared UI toolkit were looked at and turned down: see [DESIGN.md](DESIGN.md#rejected-alternatives).

## The list

| Area | Apple TV | Android TV |
|---|---|---|
| **Starts from the launcher** | System | `LEANBACK_LAUNCHER` and a banner in the manifest. One APK for phones and TVs, with nothing required of the device |
| **Moving focus** | The focus engine: the Siri Remote's clickpad and swipe drive it, with no code of ours. Rows and pads are `focusSection()`s. Nothing uses `onTapGesture` or hover | Compose's D-pad focus. `FocusBox` is the one focusable surface. Nothing depends on touch or hover |
| **Seeing focus** | `.card` buttons lift, as the system does it | A 3dp ring and 5% larger, with no animation. Not on a touch screen |
| **First focus** | `prefersDefaultFocus` in a `focusScope` | `requestFocus` on the likeliest control |
| **Focus after Back** | Explicit on Home. Elsewhere the system's, unverified | Remembered per screen by `focusKey`, and restored |
| **Disabled controls** | Never `.disabled`, which loses focus | Keep focus and do nothing, and a screen reader is told |
| **Back and Menu** | `onExitCommand` steps back through sign-in. Whether Back leaves `AVPlayerViewController` inside a stack needs checking | Back goes up one level; only Home leaves the app. Search and Profile go to Home |
| **Ten-foot sizes** | `Tokens.swift`: gutter 90, edge 60, targets 48, system text styles | `TvMetrics` in `Theme.kt`: gutter 58, edge 27, targets 48, text a quarter larger. All from the server's design tokens |
| **Typing** | `TextField` opens the system keyboard | A text box can be left with up and down. Whether the keyboard gets in the way on a real TV needs checking |
| **Signing in from a phone** | Code on the TV, approved on a phone, with a QR code | The same, and six digits typed with arrows and OK |
| **Finding a server** | `NWBrowser` | `NsdManager` |
| **Playback** | AVPlayer. No MKV, so the server remuxes it, nearly for free | Media3. MKV plays directly |
| **Asking the device what it plays** | `availableHDRModes`, `VTIsHardwareDecodeSupported`, output channels | `MediaCodecList`, the display's HDR types, `AudioCapabilities` |
| **HDR** | `appliesPreferredDisplayCriteriaAutomatically` | `SurfaceView` and the display's reported types. `dv5` only with a Dolby Vision decoder |
| **Frame rate** | The same setting | Media3's default, which only switches when it's seamless. Turning on full switching is an experiment for a real TV |
| **Audio passthrough** | Left to AVPlayer | Media3 passes through what `AudioCapabilities` reports over HDMI |
| **Remote commands, now playing** | `externalMetadata` and the system player | `MediaSession`, while the player is open |
| **Top shelf or channels** | Top Shelf extension, reading a file the app writes. No network or token in it | **Not built.** See below |
| **Live TV** | **Not built** | **Not built** |
| **Screen readers** | VoiceOver labels and groups | TalkBack labels, roles, states and live regions |

## Android TV, step by step

1. **Build it.** This needs the Android SDK: see [OWNER-STEPS.md](OWNER-STEPS.md). `gradle assembleSideload` in `android/`.
2. **Run it on an emulator.** Android's emulator runs under WSL, which has `/dev/kvm` here, with the
   `system-images;android-36;android-tv;x86_64` and `system-images;android-36;default;x86_64` images.
3. **Check with a D-pad**, in this order, since each one has never been seen: starting up; finding a server; the number
   pad; Home; a row; Back returning focus; the seek bar; the track pickers; Back from the player.
4. **Then a cheap TV stick**, which is the device this app is judged on.
5. **Channels.** The Watch Next row and a channel of our own (`androidx.tvprovider`). Its pictures are the question: the
   launcher can't send a sign-in, so it needs either local copies behind a read-only `ContentProvider` or a stream token
   in the address. Local copies are the safer of the two, and match what the Top Shelf does. It also needs a `wittymedia://`
   link into the app, with digits only, as on Apple TV. Left out until there's a device to see it on, because each of
   those adds something exposed to other apps.
6. **Google Play's TV checks** want a banner, no required touch screen (done), and a D-pad path to everything.

## Apple TV, step by step

1. **On a Mac:** `xcodegen generate`, and fix what the first compile finds. Availability of newer SwiftUI calls and
   concurrency strictness are the likeliest.
2. **Choose a team** for `WittyMedia-tvOS` and `WittyMedia-TopShelf`, and tick the App Group on both. Without it the Top
   Shelf is simply empty.
3. Work through the Apple TV list in [OWNER-STEPS.md](OWNER-STEPS.md).

**Games on a PC:** with no web view, an Apple TV can only start the game on the PC and say what to do next. No
Moonlight client on Apple devices has a URL scheme, and its GPL-3.0 code can't go inside this app. A separate Apple TV
app under the GPL, published on its own terms, is the only way to do better, and that's the owner's call.

## What the API gives a TV

- **`/capabilities`** says which apps work with this server: see "Which app works with which server" in the API guide.
- **Stream tokens** let a player with no way to set headers open media. AVPlayer is that player, so every media route a
  TV needs has to accept one. Live channels didn't, and now do: `GET /tv/{key}/tune?streamToken=1`.
- **`/playback`** takes the device's real abilities and answers with the decision, and `explain` in plain words.

## Not started, on either TV app

Live TV and the guide, discs and their menus, games other than on someone's own PC, books and photos. The server's API has
what they need: [its guide](https://github.com/wittywilla/WittyMediaServer/blob/master/docs/CLIENT-API.md) has a list called
"What a TV app must build itself". Each plainly says it can't play yet, rather than failing.
