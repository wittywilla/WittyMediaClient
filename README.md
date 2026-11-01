# WittyMediaClient

Apps that connect to a WittyMediaServer, for TV boxes, phones, tablets and desktops. You need one if you'd rather not use a browser on that device. Most of this is early, and [Platforms](#platforms) says how far each one has been run.

## What it does

- **Finds your server** on the network, or takes its address, and signs in with a code or a password. It checks the server's identity first.
- **Plays your films and shows,** with resume, on the native apps. The desktop app is a frameless window around the server's web interface, so it has everything the server has.
- **Works with a remote, a keyboard or a touch screen.**
- **Plays games on someone's own PC** through the server's page where it can, with the separately installed Moonlight app as the fallback. No part of that has reached a real PC from these apps yet.

Native apps say plainly that an item can't play yet, rather than failing, for anything but video and games on someone's own PC. Music and books need the desktop app or a browser for now.

| Folder | What it is |
|---|---|
| [`desktop/`](desktop) | Windows, macOS and Linux: Electron around the server's web interface |
| [`android/`](android) | Android TV, Google TV, Fire TV, phones and tablets: Kotlin, Compose, Media3 |
| [`apple/`](apple) | Apple TV, iPhone, iPad and Mac: SwiftUI, AVPlayer |
| [`shared/`](shared) | What every app shares, as plain data: themes, wording, button meanings and test cases |
| [`docs/`](docs) | [Installing and removing](docs/INSTALLING.md), [design](docs/DESIGN.md), [status](docs/PLATFORMS.md), [porting to TVs](docs/PORTING.md), [what the owner needs to do](docs/OWNER-STEPS.md) |

How to use your server is in **Help** inside WittyMediaServer.

### Logs

Each app keeps a small log of its own, and reports errors to the server it is connected to. Those reports go
to that server and nowhere else: there is no telemetry and no other address. The owner can turn them off with
"App errors" in the server's settings, and reads them in the server's log, under `clients`.

| App | The file | How to reach it |
|---|---|---|
| Desktop | `logs/client.log` in the app's data folder, 2 MB and three files at most | **Help** in the title bar: "Open logs folder" and "Copy diagnostic info". The connect screen has the link too |
| Android | `logs/client.log` in the app's private storage, 1 MB and three files at most | Profile, "This app's log". Errors reach the server's log |
| Apple | `logs/client.log` in the app's caches, 1 MB and three files at most | Not yet: no screen for it. Errors reach the server's log |

**What is kept and sent:** crashes, what stopped working in the app (with its reason and exit code), failed requests
with their request ID, playback errors with their stream ID, and failed connections, plus the app's version and
the system's name and version. The desktop app's file also has the address that failed, which isn't sent. The server's
page reports its own errors, so the desktop app doesn't repeat them.

**What never is:** tokens, passwords, cookies, stream addresses' secrets and file contents. Text is cleaned before it's
written anywhere, by the rules tested in `shared/data/redaction-cases.json`.

A report that fails is dropped. Repeats are grouped with a count, and nothing is ever tried again in a loop.

## How to get it

**Desktop.** Each release has installers, made by `electron-builder` from `desktop/`:

| You have | Download |
|---|---|
| Windows 10 or later | `wittymediaclient-<version>-windows-amd64-setup.exe` |
| A Mac with Apple silicon | `wittymediaclient-<version>-macos-arm64.dmg` |
| A Mac with an Intel chip | `wittymediaclient-<version>-macos-x64.dmg` |
| Debian, Ubuntu and relatives | `wittymediaclient-<version>-linux-amd64.deb` |
| Fedora and relatives | `wittymediaclient-<version>-linux-amd64.rpm` |
| Any other Linux | `wittymediaclient-<version>-linux-amd64.AppImage` |

They aren't code-signed yet, so Windows and macOS warn about them. Each upgrades in place and removes cleanly, down to your settings if you ask: [Installing and removing](docs/INSTALLING.md) has the steps and every folder involved.

**Android.** Each release has a sideload `.apk`, the same one for phones and TVs. It's signed with a throwaway key and is for testing, so it can't update to a store version without uninstalling first. There's no store listing yet.

**iPhone, iPad, Apple TV.** There's nothing to download yet. They need a Mac to build.

## What it needs

- A WittyMediaServer to connect to. The native apps talk to its client API, which is in **Help** inside the server.
- **Desktop:** Windows 10 or later, macOS, or Linux on x64. It brings its own Electron.
- **Android:** Android 6 or later. Fire TV needs Fire OS 6 or later.
- **Apple:** iOS 16, tvOS 16, or macOS 13, or later.
- **Games on a PC:** the Moonlight app, installed separately, only where it's the fallback.

## Platforms

| Platform | Where it stands |
|---|---|
| Windows 10 and later | Run from source and as a packaged app. The setup and uninstaller ran under Wine, not on real Windows |
| Linux | `.deb` and `.rpm` installed, opened on a virtual screen, upgraded and removed in containers. No real desktop yet |
| macOS | The workflow is set up to build it, and that has not run yet. It has never been launched |
| Android TV | Run on an emulator, Android 16, with arrow keys and OK only |
| Android phones | Run on emulators, Android 16 and Android 6. Android 7 to 15 not run |
| Android on x86 and ARM | The emulators were x86_64. No ARM device has run it |
| Google TV, Fire TV, tablets | Compiled, never run |
| Apple TV, iPhone, iPad, Mac | Written. Never compiled by Apple's tools, as that needs a Mac. Expect compile errors |
| FreeBSD, KDE's Plasma Big Screen | Target systems. This branch has no build for them yet |

**No real device or remote has touched any of the Android builds,** and finding servers hasn't been tried on a real network anywhere. [Platform status](docs/PLATFORMS.md) says exactly what was seen and what wasn't.

## Building and testing

**Desktop.** You need [Node.js](https://nodejs.org) 22.12 or newer.

```bash
cd desktop
npm ci
npm start
```

```bash
npm test
```

```bash
npm run test:app
```

`npm test` runs the app's rules with no window. `test:app` runs the real app against a stand-in server on 127.0.0.1, with a window for a few seconds. It replaces the network search, so the Windows firewall doesn't ask anything, and opening a browser and the Help menu, so nothing outside it starts. Set `WMC_SHOTS` to a folder for a picture of each screen. `npm run package:win`, `package:linux` and `package:mac` make the installers, and `scripts/test` has the checks that really install them.

In the app, Tab moves around the page. **F6** moves between the page and the title bar, where the arrow keys move along the bar and Escape goes back to the page. **Change server** signs out of the server you're leaving.

**Android.** CI uses Java 17 and Gradle 9.8.2.

```bash
cd android
gradle testDebugUnitTest assembleSideload
```

**Apple.** Run on any system with Swift:

```bash
cd apple/WittyKit
swift test
```

The apps themselves need a Mac and XcodeGen: see [what the owner needs to do](docs/OWNER-STEPS.md).

**Shared data.** The sample server answers those tests use are checked against a real server with `WMS_TOKEN=<token> node shared/scripts/check-fixtures.mjs <server address>`. After a theme changes in the server, rerun `node shared/scripts/build-themes.mjs` with a clone of WittyMediaServer beside this one, or `WMS_THEMES` set to its `themes` folder. CI fails if `shared/data/themes.json` is out of date.

## Licence

Apache-2.0: see [LICENSE](LICENSE) and [NOTICE](NOTICE). Any redistribution must keep the NOTICE attribution.

Third-party parts, by the app that ships them, are listed in full in [NOTICE](NOTICE):

- **Desktop:** Electron (MIT), which bundles Chromium and FFmpeg. Their licences ship with every build, in `LICENSE.electron.txt` and `LICENSES.chromium.html`.
- **Android:** AndroidX, Jetpack Compose, Media3, ZXing core, Coil, OkHttp, Okio, Kotlin and its libraries (all Apache-2.0), and Bouncy Castle (MIT).
- **Apple:** only Apple's own system frameworks.

Moonlight is a GPL-3.0 program these apps only start. Nothing of it is copied, linked or bundled.

## Legal

WittyMediaClient is an independent open-source project. It isn't associated with, sponsored by or
endorsed by any device or platform maker, publisher, rights holder or service. It connects to a
server its owner runs. What's on that server is theirs, not this project's: the project, its
contributors and affiliates don't provide, host, endorse or check it. Any third-party names here
only describe what it works with, and belong to their owners. It's provided “as is”, with no
warranty; see [LICENSE](LICENSE). Local law applies to how you use it. This isn't legal advice.
