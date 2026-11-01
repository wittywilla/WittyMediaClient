# Platform status

What each client can do, and how far each claim has actually been checked. This page is meant to
stay honest: **written** does not mean **works**.

| Word | Meaning |
|---|---|
| **Ran** | Run for real on this development machine, against a real server, with automated checks. |
| **Ran on an emulator** | Built into an APK and used on Android's emulator against a real server, and the screenshots looked at. No real device or remote has touched it. |
| **Compiled** | It builds and its unit tests pass, but it has never been started on a device or emulator. Expect problems at run time. |
| **Written** | The code exists but has never been compiled, let alone run on a device. Expect mistakes. |
| **Not started** | Nothing exists yet. |
| **Blocked** | Needs something only the owner can get. |

**Android has run on emulators and on nothing else.** [Android, as of 0.2.1](#android-as-of-021) lists what was seen and what
wasn't. Using it for the first time found real bugs that nothing before it could, so anything on that list marked as not run
should be expected to have some too.

## Platforms

| Platform | Status | Notes |
|---|---|---|
| Windows 10 and later | **Ran** | From source and as a packaged app. The setup and uninstaller ran under Wine, not yet on a real Windows. |
| macOS | **Written** | The desktop app builds for it in CI, and has never been launched. Its uninstaller only ran on Linux with a stand-in home folder. |
| Linux | **Ran** | `.deb` and `.rpm` installed, opened on a virtual screen, upgraded and removed in containers. No real desktop yet. |
| Android TV | **Ran on an emulator** | Android 16, 1080p, with arrow keys and OK only. Same APK as phones. No real TV or remote yet. |
| Google TV | **Compiled** | Not run: its emulator images come under a licence that hasn't been accepted. It should behave as Android TV does, but nobody has seen it. |
| Fire TV | **Compiled** | Not run: no image for it here. Needs Fire OS 6 or later: the first Fire TV Sticks are too old for Compose. |
| Android phones | **Ran on an emulator** | Android 16 in full, and Android 6 (API 23, the oldest it supports) for connecting, playing and a network drop. No real phone yet. |
| Android tablets | **Compiled** | Not run. They use the phone's screens with wider margins. |
| Apple TV | **Written** | Never compiled. Needs a Mac to install. |
| iPhone, iPad | **Written** | Never compiled. Needs a Mac to install. |
| Mac | **Written** | Never compiled. |
| Windows 7 | **Not started** | Needs the owner's decision: see [the design](DESIGN.md#windows-7). |
| LG webOS, Samsung Tizen | **Not started** | The connect screen they would use works without the desktop app, in the same browser engine as the desktop app. Older TV browsers are untested, and no package exists. |
| Roku | **Not started** | Needs its own app in BrightScript. |
| Browsers | Works today | The server's own web interface. Installing it as an app needs HTTPS. |
| PlayStation, Xbox, Nintendo | **Blocked** | These need approved developer programmes. |

## Connecting

| Step | Desktop | Android | Apple |
|---|---|---|---|
| Type an address, with the shared rules | Ran | Ran on an emulator, Android 6 | Written |
| Refuse plain HTTP to a public address | Ran | Ran on an emulator, Android 6 | Written |
| **Find servers on the network** | Ran, with packets built in tests only | Ran on an emulator, Android 16, through its network translation and not on a real network: see below. Android 6 found none | Written |
| **Security code typed on the device** | Ran | Ran on an emulator: touch and number keys on phones, arrows and OK on TV, right and wrong codes | Written |
| Check the server's identity before sending a sign-in | Ran | Ran on an emulator, in both the debug and the shrunk build, Android 6 and 16 | Written |
| The warning when a different key answers | Ran | Ran on an emulator: another server put on the same address, phone, with Back as the way out. "Trust it" wasn't pressed | Written |
| Look for a saved server by its ID when its address stops answering | Not built: it lists what it finds | Compiled, never run | Written |
| TV shows a code, approved on a phone | Not needed | Ran on an emulator: the code was approved with the same requests a phone's browser makes, not with a phone. The QR code is on screen and nothing has scanned it | Written |
| Password and profiles | Ran, through the web interface | Ran on an emulator, phone: the profile list, a wrong and a right password | Written |
| Remember the server | Ran | Ran on an emulator: reopening goes straight to Home, and signing out ends the session on the server | Written |

Finding servers and the security code are the owner's main requirement. **The security code has run on Android's emulator
and the desktop. Finding servers has not yet been tried on a real network anywhere.**

**How finding servers ran on the emulator.** The app found real servers by real mDNS, through Android's own `NsdManager`, and
connected to the one chosen. But the emulator sits behind network translation, so its questions reach the server from another
port, and the server rightly answers those with a 10-second lifetime and straight back. On a real network it answers from
port 5353 to everyone, with lifetimes of 2 minutes and more. So this proves the app's half and the server's answer, not a
server announcing itself to a whole network, and not a phone and a server on one Wi-Fi. Android 6 found nothing at all in the
same place. Whether that is its older mDNS code, the emulator, or something a real device would also show isn't known, so the
address box is the safe route there.

**That run did find a bug.** Android reported the servers lost and found again every 22 seconds, and each report took their
rows off the screen and a remote's focus with them. A server now only leaves the list after 45 seconds of being gone.

**Checked for Android,** on this machine and without a device:

- The real signed answer in `shared/fixtures/identity.json` verifies, and tampering with its signature,
  key, server ID or nonce makes it fail.
- Over real connections to a stand-in server that really signs: a fresh nonce each time, no token sent
  with the question, a look-alike noticed, a replayed answer refused, redirects not followed, and an
  oversized answer refused.
- Against a real server built from `test/all-merged`: it is recognised, its key is proved and pinned, a
  different pin is noticed, a wrong code is refused, a right code signs in and the token works, and a used
  code is refused.
- The number pad's rules, including that every key can be reached with arrows alone, and what each
  identity result leads to.
- That the Ed25519 code survives shrinking into the release build. The shrunk build signed in with it on the Android 16 TV
  emulator. The debug build did so on Android 6. The shrunk build hasn't run on Android 6.

**Not checked for Android:** a real remote, a real device, a real network, and `NsdManager` on real hardware, which differs
between devices and has known problems on some. Everything else is in [Android, as of 0.2.1](#android-as-of-021).

**The Apple apps have never been compiled by Apple's tools,** as that needs a Mac. Expect compile errors. See
[Apple, as of 0.2.0](#apple-as-of-020) for exactly what has and hasn't been checked.

**Known limits of the identity check,** on every client: the very first connection trusts whatever key it
is shown, so someone already impersonating the server at that moment gets pinned, and would see a code
typed for them. Comparing the fingerprint with the one on the server's `/pair` page catches that, and HTTPS
prevents it.

**Differences from the desktop app.** The native apps re-check when brought back to the front as well as at a cold
start, since TV apps are rarely closed. The desktop app also holds a code or a "trust it" to the very key the person
was shown, by asking again just before sending; the native apps don't yet compare those two answers.

**Left out of the native apps:** the UDP question, because mDNS is the way the API guide gives and Apple
can't use it without a special permission. If a device or network turns out to block mDNS, adding it on
Android is the next step. On Android, an `http://` address that redirects to `https://` is reported as not being a
server, and needs the `https://` address typed. The Apple apps try the `https://` address when it's the same host, and prove it
again from the start, without following the redirect.

## Features

| Feature | Desktop | Android | Apple |
|---|---|---|---|
| Home, libraries, shows, item pages | Ran | Ran on an emulator | Written |
| Video with resume | Ran | Ran on an emulator | Written |
| Audio and subtitle tracks | Web interface; not checked here | Ran on an emulator. Subtitles were seen; audio only by the player's own log, as the emulators had no sound | Written |
| Skip intro, next episode countdown | Web interface; not checked here | Ran on an emulator | Written |
| Themes | Ran, including the title bar | Colours from the server's theme only, no picker | Colours from the server's theme only, no picker |
| Search | Web interface; not checked here | Ran on an emulator, for films and shows, with the TV's keyboard too | Written, for films and shows |
| Music, audiobooks, podcasts | Web interface; not checked here | Not started | Listed, with a note that they play in a browser for now |
| Books and comics | Web interface; not checked here | Not started | Not started |
| Disc menus | Web interface; not checked here | Not started | Not started |
| Games on someone's own PC | Web interface, with Moonlight as the fallback. Written; its rules ran in unit tests | Its Game PCs page opened on an emulator, no further: see below | Written; its rules ran in unit tests on Linux |
| Gaming, channels, tuners, photos | Arrive with the server | Not started | Not started |
| Own log, with errors reported to the server | The log's logic ran in tests; never run inside the app | Written and shown in the app on an emulator. A report reaching the server wasn't checked | The log's logic ran in tests on Linux; its use in the app was not compiled, and catching crashes only builds on Apple |

Native apps say plainly that an item can't play yet, rather than failing, for anything but video and
games on someone's own PC.

## Games on someone's own PC

A person's own gaming PC runs Sunshine, and the server's web interface has a Moonlight client in the page
that plays it. The apps show that page where they can. The separately installed Moonlight app is the fallback:
a GPL-3.0 program they only start, with nothing of it copied, linked or bundled. **No part of this has ever
reached a real PC or a real Moonlight from these apps, and the player has never run inside any of them.**

| | What happens on Play | How far it was checked |
|---|---|---|
| Desktop | The server's page plays it. Starting Moonlight is the fallback, and the main process checks that request | **Written.** The checks, finding the program, starting a stand-in for it and who may lock the mouse ran in unit tests, and the real app answers a server's page with those checks (`npm run test:app`). Moonlight itself has never been started by it here. |
| Android, phones and tablets | The player in a web view, with "Open in Moonlight instead" as the second choice. A "Game PCs" entry opens the same pages | **Ran on an emulator, as far as the Game PCs page.** It opens signed in, on Android 16. Its decisions ran in 16 unit tests: which comes first, only the same server staying in the web view, the shape of the sign-in cookie, and that a server can't name another app. The player in the web view and the intent have never run. |
| Android TV, Fire TV | Moonlight first, then "Play in this app instead" | **Compiled**, as above. This path has never run, on a TV or anywhere. |
| iPhone, iPad | The player in a web view, with "Start on <PC>" as the second choice. A "Game PCs" entry opens the same pages | **Written.** The checks in WittyKit built and passed their tests on Linux, with Swift 6.1 in a container. The screens need a Mac and have never been compiled. |
| Apple TV | "Start on <PC>", then the app says to open Moonlight and Resume | **Written**, as above. |
| Mac | Running the desktop Moonlight if it's in `/Applications`, the player in the Mac's own browser, or "Start on <PC>" | **Written**, as above. |

**Why TVs don't play in the page first:** whether a TV's web view gives a page the Gamepad API at all is doubtful,
and a remote alone can't work the player's mouse and keyboard. Moonlight is built for a TV.

**A decision for the owner: Apple TV.** tvOS offers apps no web view at all, and no Moonlight client on any Apple
device has a URL scheme, so this app can't do more than start the game on the PC. The only way to do better is a
separate Apple TV app under the GPL, published on its own terms. The App Store and GPL-3.0 are widely held to
conflict, so that needs thinking through first. Moonlight's code never goes inside this app either way.

**Known limits:**

- The sign-in reaches a web view as the server's own cookie, set for its address only. As with any cookie, that
  address's other ports would receive it if the page went there, which the web view refuses to do.
- On plain http, browsers hide game controllers from a page, so a web view may too. Whether they work over HTTPS in
  either web view has not been seen.
- Leaving the player with the system's Back relies on the server noticing that the connection closed.
- The Mac app is sandboxed, and a program it starts stays inside that sandbox, so running Moonlight may not
  work there. Nobody has tried. The other two ways are offered beside it.
- A server only offers a command to run to the desktop kind of client, so the Mac app asks as `desktop`
  rather than `apple`, on purpose.
- Android can't tell that Moonlight doesn't know a PC yet. Moonlight says so itself, and the app has the setup
  steps a button away.

## Android, as of 0.2.1

Run in headless emulators under WSL, with hardware virtualisation and software graphics, against a real server built from
`release/0.6.0-alpha`, with test films and an episode set made here. Driven with `adb`, read with screenshots and
`uiautomator`, and the screenshots looked at. Unit tests and Android lint pass, and lint checks every call against API 23.

| Emulator | Build | What it had |
|---|---|---|
| Phone, Android 16 (API 36), 1080×2400 | Debug | Everything under "Phone" below |
| TV, Android 16 (API 36), 1080p | Sideload, shrunk with R8 | Everything under "TV" below, with arrow keys, OK and Back only |
| Phone, Android 6 (API 23), 1080×1920 | Debug | Everything under "Android 6" below |

**Both, on Android 16.** Starting up, finding the server, a code signing in, Home with its hero and rows, libraries, a show and its
seasons, an item page, search. A film and episodes playing with a real picture seen: H.264 and AAC in Matroska played as they are,
and HEVC 10-bit with AC-3 converted by the server and played as HLS. Resuming at the saved place, also on another device, and
Start over. Seeking, pausing, Skip intro by itself and within the controls, the next-episode countdown going on to the next
episode, and leaving with Back. Signing out, which ends the session on the server.

**Phone.** Rotating, with the screens laid out again and the picture kept. 44dp or more on every touch target on the eight screens
measured. Labels in the accessibility tree: TalkBack isn't on this image, so nothing has spoken them. Audio tracks, by the
player's own log moving to the chosen track. English subtitles seen on the picture. The warning for another key. A wrong password.
The network dropped in mid-film: a plain message with Try again, then back by itself at the same place. The Game PCs page in a web
view, once it had started, as far as its list: no PC was added. Dark system-bar icons on a light theme, if the theme test below says so.

**TV.** First focus on every screen, with the ring seen in screenshots. Left and right staying in a row, and up and down between rows.
Focus returning after Back, and to the button that opened a list. The number pad with arrows and OK, right and wrong codes. The code
shown on the TV, approved. French subtitles seen on the picture, at a size that reads across a room in a screenshot; that's as near as
this comes to ten feet. Search with the system's TV keyboard, then Back to shut it and down to the results. Licences scrolling.

**Android 6.** Typing an address, with a public plain-http one refused and a dead one explained. A code signing in, so Keystore and
Ed25519 both work there. Home, and a film playing on its older OMX decoders. Seeking, and a saved place from the TV. Mobile data
dropped in mid-film and back, which came back by itself at the same place, through the older network callback this version needs.
Reopening with the kept sign-in. Android 7 to 15 haven't been run, and nor has the shrunk build on Android 6. TV images older than
16 weren't run either.

**Not seen, and only a person can see most of it:**

- **Any real device or remote.** A cheap TV stick is the test that matters most, for speed above all: nothing here says how smooth it is.
  On these emulators, with other work holding the machine, a shrunk build started in 1 to 6 seconds and a debug build took up to 21.
- **Sound.** The emulators had none. Tracks switched, and nothing has been listened to.
- **A real network:** see [Connecting](#connecting).
- **TalkBack speaking,** and any other screen reader.
- **HDR, surround and passthrough, 4K, frame-rate switching.** The emulator reports none of them.
- **Tablets, foldables, gesture navigation** (three buttons were on), very large text, Google TV and Fire TV.
- **A game controller,** Moonlight, and playing a game on a PC: no part of it reached a real PC.
- **The light themes on TV,** two-factor accounts, and a server that has moved to a new address.
- **Hardware decoders.** The emulator's are software or its own.

## Apple, as of 0.2.0

**Run, on Linux with Swift 6.1 in a container:** every test in `apple/WittyKit` with `swift test`, including real connections to a
stand-in server: redirects not followed, oversized answers dropped, version and revision checks, and cancelling. Signatures can't be
verified on Linux, as it has no CryptoKit. Every answer is refused there, and those tests only run on Apple platforms.

**Only checked for syntax:** every file in `apple/App` and `apple/TopShelf`, with `swiftc -parse`. The app's own files were also
type-checked against small stand-ins written for SwiftUI, AVFoundation and the rest, for each of the three platforms. That catches
wrong names and types between the app's own files, and says nothing about whether Apple's real frameworks accept the code.

**Never done:** compiling with Xcode, running on any device or simulator, focus with a real remote, VoiceOver, AVPlayer playing
anything, the Keychain, the web view, the Top Shelf, or generating the Xcode project from `project.yml`, which has only been read.

| Part | State | Most likely to need work |
|---|---|---|
| Whole app | **Written** | Availability of SwiftUI calls at the deployment targets, and strict concurrency in newer Xcode |
| iPhone pill bar | **Written** | Whether the bar's inset reaches the scrolling content on iOS 16 |
| Apple TV focus | **Written** | First focus, restoring focus, and how far lifted cards clip at the edges |
| Top Shelf | **Written** | Whether poster files in the App Group load, and the App Group's signing |
| Device capabilities | **Written** | What each device really reports, and whether the choices fit real files |
| Picture in picture | **Written** | Whether pausing in the background interferes. Plain video pauses when the app goes to the background |

**Known limits:**

- The server's growing streams start the player's clock at the place they start from, so the system's seek bar shows time from there,
  not the film's own time. It can only seek within what exists so far. Going further needs a track change or a new start.
- Now-playing information comes from the system's player. It isn't written by hand, so a screen other than the player would need its
  own when music arrives.
- Posters are kept in memory, not on disk, so they're fetched again each time the app starts.
- The hero is one picture from the server's featured list, and doesn't turn or page.
- Music and every other type the app can't open only say so. Search finds films and shows, not episodes or music.
- A two-factor prompt on password sign-in isn't built. Those accounts can sign in by code.
- There are no tests of the screens themselves. Anything that can be tested without one is in WittyKit.

## Not done yet in the native apps

- A prompt for two-factor codes on password sign-in. Those accounts can use code sign-in instead.
- On Android: playing in the background or picture in picture, TV channels, Live TV, a choice between a file's several pictures,
  and a baseline profile for faster starts.
- App icons and TV artwork. Android has a placeholder, Apple has none, and the desktop app has
  Electron's default icon.

## Checked on the desktop client

On Windows, from source and as a packaged app, against both today's server and the `client-contract`
branch, 24 checks passed using real key presses:

- The address screen, including refusals in plain words.
- The server's page has no access to the app.
- Choosing a profile and typing a password.
- A video plays: the clock advances, it seeks, and a frame was measured and looked at to confirm a
  real picture.
- The resume position reaches the server.
- The title bar follows the theme.
- Up, down, OK and Back on the connect screen.

`npm run test:app` runs the app itself against a stand-in server on 127.0.0.1, with the network search replaced. It
passes on Windows from source, and its main journey passes inside a package with every fuse on (encrypted cookies,
checked package, no `file://` privileges):

- The code screen, a refused code, a key changing mid-screen, signing in, and the cookie being out of a page's reach.
- What a hostile page can't do: open programs or files, reach the connect screen, open things outside without limit, be
  redirected away, or save anything from elsewhere.
- F6 and the keys along the title bar. Change server ending the session here and on the server. The warning for another
  key, and trusting that key rather than a later one.
- Starting with a remembered server, another key at it, a server that has gone, a damaged state file and a bad
  certificate, which also proves that listening to `certificate-error` doesn't accept one.

## Not checked on the desktop client

- **Sound.** Nothing here listens to it.
- **Game controllers** and real TV remotes. Key presses were simulated.
- **Linux** on a real desktop. The packages opened on a virtual screen in containers.
- **macOS** at all.
- **The network search with real sockets** on this version: it would ask the Windows firewall.
- The package check failing as it should when the package is changed.
- A server asking for a client certificate, which needs one in the system's store.
- Installers on a real Windows, and very low-end hardware.
- Screen readers. Roles, labels and live regions are checked as they appear in the page, but no screen reader has read them.
- Audio and subtitle tracks, and everything else marked "not checked here" above. They are the web
  interface's own features, displayed unchanged.
- A real look on screen. A capture of the whole window looks right, with a pale strip around its edge
  that is almost certainly how the capture draws the invisible Windows resize border.

Known and not explained: in about one in ten runs of the check without the desktop bridge (the path a
smart TV would use), simulated typing had no effect. It did not happen again once diagnostics were
added, and the cause is unknown. It could be the test or the screen.

## Other known limits

- Cookies don't go by port, so two servers at one address (the same computer on two ports) share the desktop app's
  sign-in cookie: signing in to one signs the other out, and the other is sent that sign-in if it's opened. Each
  server having a session of its own would solve it.
- The title bar can be reached by keyboard (F6), but not by a remote or a controller alone.
- `shared/data/themes.json` is generated. Merging the interface overhaul changes theme colours, so it
  must be regenerated at that point, or CI fails on purpose.
- Plain HTTP stays enabled on Android because its rules can't name "private addresses only". The app's
  own check is the only thing refusing public plain HTTP there.
- The desktop app is about 357 MB unpacked and uses Chromium's memory, so it is not the low-end
  option. On a weak PC, a browser uses less.
