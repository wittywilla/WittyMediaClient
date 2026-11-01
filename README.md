# WittyMediaClient

Apps that connect to a [WittyMediaServer](https://github.com/wittywilla/WittyMediaServer): TV boxes, phones, tablets and desktops.

**Start with [docs/PLATFORMS.md](docs/PLATFORMS.md)**, which says exactly what works and what has
never been run. Most of this is early. The Android app has run on emulators, not on a real device, and the Apple apps have not been compiled yet.

| Folder | What it is |
|---|---|
| [`desktop/`](desktop) | Windows, macOS, Linux, FreeBSD and KDE's Plasma Bigscreen: a frameless window around the server's web interface |
| [`android/`](android) | Android TV, Google TV, Fire TV, phones and tablets, one APK for ARM and x86, 32-bit and 64-bit (Kotlin, Compose, Media3) |
| [`apple/`](apple) | Apple TV, iPhone, iPad and Mac (SwiftUI, AVPlayer) |
| [`shared/`](shared) | What every app shares, as plain data: themes, wording, button meanings and test cases |
| [`docs/`](docs) | [Installing and removing](docs/INSTALLING.md), [design](docs/DESIGN.md), [status](docs/PLATFORMS.md), [porting to TVs](docs/PORTING.md), [what the owner needs to do](docs/OWNER-STEPS.md) |

The native apps talk to the API described in [`docs/CLIENT-API.md`](https://github.com/wittywilla/WittyMediaServer/blob/master/docs/CLIENT-API.md) in the server's repository.

## Installing the desktop app

[The releases page](https://github.com/wittywilla/WittyMediaClient/releases) has a setup for Windows, a disk image for
macOS, and a `.deb`, `.rpm` and AppImage for Linux. Each one upgrades in place and removes cleanly, down to your settings if
you ask: [docs/INSTALLING.md](docs/INSTALLING.md) has the steps and every folder involved.

## Trying the desktop app from source

You need [Node.js](https://nodejs.org) 22.12 or newer, and a WittyMediaServer to connect to.

```bash
cd desktop
npm ci
npm start
```

Tab moves around the page. **F6** moves between the page and the title bar, where the arrow keys move along the bar and
Escape goes back to the page. **Change server** signs out of the server you're leaving.

### Installing, and removing

[docs/INSTALLING.md](docs/INSTALLING.md) has every system: Windows, macOS, Linux, FreeBSD and Plasma Bigscreen, and what each one leaves behind when it's removed.

The FreeBSD package holds only the app, under a megabyte, and uses the system's Electron from the ports tree, which
`pkg` installs with it. See [docs/PORTING.md](docs/PORTING.md#freebsd).

### On a TV

In a [Plasma Bigscreen](https://plasma-bigscreen.org) session, the Linux app opens as a TV app by itself: the whole
screen, no title bar, the server's big screen mode, and everything reachable with arrows, Enter and Back. Install a `.deb`,
`.rpm` or `.pacman` so it appears in the launcher. An AppImage doesn't add itself to any launcher.

Anywhere else, `wittymediaclient --tv` asks for the same, and `--no-tv` turns it off inside Bigscreen. Back at the top of
the app opens a small menu with Change server and Quit.

## Logs

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

## Tests

```bash
cd desktop
npm test          # the app's rules, with no window
npm run test:app  # the real app against a stand-in server on 127.0.0.1, with a window for a few seconds
```

`test:app` replaces the network search, so the Windows firewall doesn't ask anything, and opening a browser and the Help
menu, so nothing outside it starts. Set `WMC_SHOTS` to a folder for a picture of each screen.

For a system that can't run the stand-in, such as a virtual machine, this runs the real app against a real server, with
key presses alone, and plays a video. The server needs a film in its first library:

```bash
WMC_SERVER=http://192.168.1.20:8096 WMC_USER=me WMC_PASSWORD=... npm run test:real -- --tv
```

On FreeBSD, run Electron yourself, as the `electron` npm package has no build for it:
`/usr/local/share/electron42/electron test/app/real-server.js --tv`. Set `WMC_APP` to an installed `app.asar` to test that
instead of this folder.

```bash
cd apple/WittyKit
swift test
```

```bash
cd android
gradle testDebugUnitTest lintSideload assembleSideload
sh scripts/check-abis.sh app/build/outputs/apk/sideload/app-sideload.apk
```

`lintSideload` is what keeps Android 6 honest: it fails on a call that version doesn't have. `check-abis.sh` says which
processors the APK carries, and fails if a native library is missing for any of the four.

The sample server answers used by those tests are checked against a real server with
`WMS_TOKEN=<token> node shared/scripts/check-fixtures.mjs <server address>`. After a theme changes in the server, rerun
`node shared/scripts/build-themes.mjs` with a clone of WittyMediaServer beside this one (or `WMS_THEMES` set to its
`themes` folder); CI fails if `shared/data/themes.json` is out of date.

## Legal

WittyMediaClient is an independent open-source project. It isn't associated with, sponsored by or
endorsed by any device or platform maker, publisher, rights holder or service. It connects to a
server its owner runs. What's on that server is theirs, not this project's: the project, its
contributors and affiliates don't provide, host, endorse or check it. Any third-party names here
only describe what it works with, and belong to their owners. It's provided “as is”, with no
warranty; see [LICENSE](LICENSE). Local law applies to how you use it. This isn't legal advice.
