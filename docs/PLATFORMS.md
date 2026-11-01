# Platform status

What each client can do, and how far each claim has actually been checked. This page is meant to
stay honest: **written** does not mean **works**.

| Word | Meaning |
|---|---|
| **Ran** | Run for real on this development machine, against a real server, with automated checks. |
| **Compiled** | It builds and its unit tests pass, but it has never been started on a device or emulator. Expect problems at run time. |
| **Type-checked** | Its code compiles against Android's own classes, and its tests pass, but no APK has been made from it. Its manifest and resources have only been read. |
| **Written** | The code exists but has never been compiled, let alone run on a device. Expect mistakes. |
| **Not started** | Nothing exists yet. |
| **Blocked** | Needs something only the owner can get. |

**Android 0.2.0 has not been built into an APK.** This machine has no Android SDK, because installing one means
accepting Google's licence terms, which is the owner's decision: see [OWNER-STEPS.md](OWNER-STEPS.md). Instead, all of its
Kotlin was compiled against AOSP's `android-all` jar and the real libraries, Compose's compiler included, with 113 tests
passing, one of them against a real server. That proves its types agree and its rules, data handling and network calls work. It
says nothing about the manifest, resources or shrinking, and **none of its screens, its player or its focus handling has
ever run**, on a device or an emulator.

## Platforms

| Platform | Status | Notes |
|---|---|---|
| Windows 10 and later | **Ran** | From source and as a packaged app. Installers are configured but not built yet. |
| Linux | **Ran** | On Ubuntu 26.04 from source, and on Fedora 44 as an installed `.rpm`. `.deb`, `.pacman` and AppImage build, and haven't been installed. See [below](#freebsd-plasma-bigscreen-and-linux). |
| FreeBSD 15.1, amd64 | **Ran** | In a virtual machine, as an installed package: picture and sound seen. Needs the system's Electron from the ports tree. See [below](#freebsd-plasma-bigscreen-and-linux). |
| FreeBSD 14, aarch64, i386 | **Not run** | The same package should work where FreeBSD has an Electron package. At the time of writing that means amd64 on 14 and 15, and only by building Electron from ports on the others. |
| KDE Plasma Bigscreen | **Ran** | The real shell 6.8.2 on Fedora 44, in a virtual machine: listed in its launcher, opened from it, video and sound seen, keys through the real input stack. Never on a TV or with a real remote. See [below](#freebsd-plasma-bigscreen-and-linux). |
| Android ARM, 64-bit | **Compiled** | In the same APK, from Android 6. Not run here: the emulators are x86. |
| Android ARM, 32-bit | **Compiled** | In the same APK, from Android 6. Not run here: see [Android's processors](#androids-processors). |
| Android x86, 64-bit | **Compiled** | In the same APK, from Android 6. This is the processor Android's emulators here use, and the `android-real` work records what was seen on them. |
| Android x86, 32-bit | **Compiled** | In the same APK, from Android 6. Not run here. |
| Android TV, Google TV | **Type-checked** | Never run. Same APK as phones. |
| Fire TV | **Type-checked** | Never run. Needs Fire OS 6 or later: the first Fire TV Sticks are too old for Compose. |
| Android phones, tablets | **Type-checked** | Never run. |
| Apple TV | **Written** | Never compiled. Needs a Mac to install. |
| iPhone, iPad | **Written** | Never compiled. Needs a Mac to install. |
| Mac | **Written** | Never compiled. |
| Windows 7 | **Not started** | Needs the owner's decision: see [the design](DESIGN.md#windows-7). |
| LG webOS, Samsung Tizen | **Not started** | The connect screen they would use works without the desktop app, in the same browser engine as the desktop app. Older TV browsers are untested, and no package exists. |
| Roku | **Not started** | Needs its own app in BrightScript. |
| Browsers | Works today | The server's own web interface. Installing it as an app needs HTTPS. |
| PlayStation, Xbox, Nintendo | **Blocked** | These need approved developer programmes. |

## FreeBSD, Plasma Bigscreen and Linux

All of this ran on this development machine, in QEMU with KVM, against a real WittyMediaServer 0.6.0 with a generated test clip
(H.264 and AAC, with a 330 Hz tone). The displays in the pictures came from the virtual machine's own screen, and key presses from
its own keyboard or X, unless it says otherwise.

| | FreeBSD 15.1 | Plasma Bigscreen 6.8.2, Fedora 44 | Ubuntu 26.04 |
|---|---|---|---|
| How it was installed | `pkg install` of the package, with Electron 42.11.10 from FreeBSD's repository | `dnf install` of the `.rpm`, with its own Electron 45.2.1 | From source, under a virtual display |
| Display | X11, on the VESA driver | Wayland, native, in the real KWin | Xvfb |
| `npm run test:real`, with `--tv` and on the desktop | 11 of 11, and 8 of 8 | Not used: the same journey was done with real keys and pictures | 11 of 11 |
| The clock moves and frames decode | Yes | Yes: the frame counter on the clip reached 10.8 seconds | Yes |
| Sound | Yes: the VM's sound card recorded the clip's tone, at 334 Hz by a rough count | Yes: 330 Hz recorded | Not checked |
| Finding servers with real packets | Found this machine's four servers, through the VM's network | Found four | Found one |
| Security code and sign-in | Real server | Real server | Real server |
| Leaving the player, and the menu at the top | Yes | Yes | Yes |
| Quit | Yes | Yes, back to the launcher | Not checked |
| Change server from the menu, signing out | Yes | Not checked | Yes |

**Seen only on Plasma Bigscreen:**

- It's listed in the launcher, with its icon and description, from an ordinary desktop entry.
- Opened from the launcher with no flags, it recognises the session and opens as a TV app.
- The on-screen keyboard appears for the address box, the page moves up to make room, and arrows and Enter typed into it.
- A virtual Xbox pad, made with `uinput`: as soon as the app opened it, the shell's input handler stopped turning it
  into key presses. Each press moved focus one step, and B opened the menu, so presses aren't handled twice.
- A sign-in made from the launcher is still there after restarting the app. No keyring wizard appears.

**Not seen, on any of these:**

- A real TV, a real remote, and HDMI-CEC. Key presses were real to the system, but a real remote may send other keys.
- Readability from across a real room. Body text is 18.75px at 1080p, from the server's big screen mode, which is how a TV browser looks too.
- Hardware video decoding. All of this was software, on a machine with plenty of power to spare.
- A real FreeBSD desktop. X11 was bare, with one small window manager. Wayland on FreeBSD hasn't been tried.
- Installing the `.deb`, `.pacman` and AppImage, though all three build.
- Flatpak. No package exists: see [PORTING.md](PORTING.md#plasma-bigscreen).
- CI's FreeBSD job. Its commands ran by hand in the VM, but the job itself needs a push to run.

**Known limits:**

- **FreeBSD's Electron is shared, so this package can't set Electron's fuses.** The launcher clears the variables those fuses
  would ignore, and developer tools stay off in an installed copy. Still, the sign-in cookie isn't encrypted on disk there. It's
  protected only by being in a folder of that user's. The package's contents aren't checked against tampering either, which
  matters less for files only root can change.
- **On a TV, the cookie isn't kept in the keyring**, on any system. Chromium's use of the keyring opens KDE's wallet wizard over the app the
  first time someone signs in. So a TV uses Chromium's plain store, in a folder only that user can read.
- **FreeBSD's ports retire each Electron within months.** The launcher falls back to the newest one present, and the build picks the
  newest one with a package. The code has to keep working across Electron versions. It's now run on 42 and 45.
- Removing or reinstalling the `.rpm` over itself drops the `/usr/bin/wittymedia` link, which is how electron-builder's scripts work.
  The launcher entry doesn't use the link. `rpm -e` followed by a fresh install puts it back.
- A real shell needs more than Fedora's `plasma-bigscreen` package installs. Without `plasma-nm` and `kscreen`, it stops at an error screen. That's
  for its packagers, and is noted in [PORTING.md](PORTING.md#plasma-bigscreen).

## Android's processors

One APK carries all four. Checked by opening a real one built from this branch, with `android/scripts/check-abis.sh` and `aapt2`:

| | |
|---|---|
| Native libraries | One: `libandroidx.graphics.path.so`, from Jetpack Compose, in all four |
| `native-code` as Android reads it | `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64` |
| Lowest Android | 6.0, API 23 |
| 16 KB memory pages | Aligned, by `zipalign -c -P 16` |
| Size | 2.9 MB |

**Why Android 6 is the lowest claim.** Media3, Activity, Core and Lifecycle, 23 libraries in all, need API 23 and won't build below it, so it's a
hard floor. Android's own lint reads every call against that version, and CI now runs it. It found the player's network watcher calling something from
API 24, which was caught rather than crashing and is fixed on the `android-real` branch, so lint is only clean with that merged. It also found two places here
that needed an annotation and no change in what they do.

**ARM older than `armeabi-v7a` isn't possible.** Android's tools dropped ARMv5 and ARMv6 in 2018, so the libraries this app depends on aren't built for them.

**Not seen:** this app running on any ARM device or any 32-bit build. Android's emulators on this x86 machine don't run ARM at a usable speed, and
it hasn't been run on a 32-bit x86 image or on Android 6. A cheap 32-bit ARM TV stick is the check that matters most.

## Connecting

| Step | Desktop | Android | Apple |
|---|---|---|---|
| Type an address, with the shared rules | Ran | Compiled | Written |
| Refuse plain HTTP to a public address | Ran | Compiled | Written |
| **Find servers on the network** | Ran, with packets built in tests only | Compiled. Its rules ran; the search itself never has | Written |
| **Security code typed on the device** | Ran | Compiled. The network side ran against a real server; the number pad has never been on a screen | Written |
| Check the server's identity before sending a sign-in | Ran | Compiled. The check ran against a real server and a real signed answer | Written |
| The warning when a different key answers | Ran | Compiled. The decision ran; the screen never has | Written |
| Look for a saved server by its ID when its address stops answering | Not built: it lists what it finds | Compiled, never run | Written |
| TV shows a code, approved on a phone | Not needed | Compiled | Written |
| Password and profiles | Ran, through the web interface | Compiled | Written |
| Remember the server | Ran | Compiled | Written |

Finding servers and the security code are the owner's main requirement. **They have only been run on
the desktop, and finding servers has not yet been tried on a real network anywhere.** The API for them
is on the `client-contract` branch, so the native apps need that merged before they can connect.

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
- That the Ed25519 code survives shrinking into the release build. Whether it then loads and runs on
  old Android versions hasn't been seen.

**Not checked for Android:** every screen, focus on a real remote, `NsdManager` finding anything, which
differs between devices and has known problems on some, and whether API 23 devices behave like newer ones.

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
| Home, libraries, shows, item pages | Ran | Compiled | Written |
| Video with resume | Ran | Compiled | Written |
| Audio and subtitle tracks | Web interface; not checked here | Compiled | Written |
| Skip intro, next episode countdown | Web interface; not checked here | Compiled | Written |
| Themes | Ran, including the title bar | Colours from the server's theme only, no picker | Colours from the server's theme only, no picker |
| Search | Web interface; not checked here | Not started | Written, for films and shows |
| Music, audiobooks, podcasts | Web interface; not checked here | Not started | Listed, with a note that they play in a browser for now |
| Books and comics | Web interface; not checked here | Not started | Not started |
| Disc menus | Web interface; not checked here | Not started | Not started |
| Games on someone's own PC | Web interface, with Moonlight as the fallback. Written; its rules ran in unit tests | Compiled | Written; its rules ran in unit tests on Linux |
| Gaming, channels, tuners, photos | Arrive with the server | Not started | Not started |
| Own log, with errors reported to the server | The log's logic ran in tests; never run inside the app | The log's logic ran in tests off Android; its use in the app was not compiled | The log's logic ran in tests on Linux; its use in the app was not compiled, and catching crashes only builds on Apple |

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
| Android, phones and tablets | The player in a web view, with "Open in Moonlight instead" as the second choice. A "Game PCs" entry opens the same pages | **Compiled.** Its decisions ran in 16 unit tests: which comes first, only the same server staying in the web view, the shape of the sign-in cookie, and that a server can't name another app. The web view and the intent have never run. |
| Android TV, Fire TV | Moonlight first, then "Play in this app instead" | **Compiled**, as above. Focus with a remote has never been seen. |
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

## Android, as of 0.2.0

**Ran against a real server** (built from this release, in WSL, with a generated test clip), from the app's own code off a device:
the address and capability checks, the identity check, a code signing in, Home, a library, search, a playback request with a
device's real abilities, opening the answer's media address with nothing but its stream token, a conversion on request, saving
progress, stopping a stream, and a signed-out token being refused.

**Ran in tests only:** the playback clock and retry rules, what each failure leads to, how a device's codecs become what the
server hears, seek steps, the QR code's cells, every theme's contrast, redaction, Moonlight's rules.

**Written and never seen working,** which is everything that needs a screen or Android itself: all screens and focus, the
player, picking up after a network drop, HDR and passthrough detection, the Keystore, `NsdManager`, the web view, TalkBack,
system bars, and the home screen's look. Expect some of this to need fixing the first time it runs.

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
- **The network search with real sockets** on this version: it would ask the Windows firewall.
- The package check failing as it should when the package is changed.
- A server asking for a client certificate, which needs one in the system's store.
- Installers, updating from an old version, and very low-end hardware.
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
- The title bar can be reached by keyboard (F6), but not by a remote or a controller alone. In TV mode it's hidden, and Back at
  the top of the app opens a menu with what a TV needs from it.
- `shared/data/themes.json` is generated. Merging the interface overhaul changes theme colours, so it
  must be regenerated at that point, or CI fails on purpose.
- Plain HTTP stays enabled on Android because its rules can't name "private addresses only". The app's
  own check is the only thing refusing public plain HTTP there.
- The desktop app is about 357 MB unpacked and uses Chromium's memory, so it is not the low-end
  option. On a weak PC, a browser uses less.
