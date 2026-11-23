# Smoke tests

End-to-end checks of the apps against a real server, on every pull request into a release branch (`v0.*`), in `.github/workflows/smoke.yml`. Each step leaves a log and a screenshot in the run's artifacts (`smoke-desktop`, `smoke-android-phone`, `smoke-android-tv`).

The server is built from WittyMediaServer's branch of **the same name as this pull request's branch** when one exists, so a change made in both repositories is tested together; otherwise from the release branch the pull request targets. Its setup (an administrator, a film, an album, a Game Boy game, WittyPlay, WittyTuner's demo tuner) and the tiny media are the server repository's `scripts/smoke` (see its README). The web app and remote access through a WittyRelay are tested there.

## Desktop app (`desktop`)

The real Electron app under a virtual screen, with the harnesses in `desktop/test/app`:

| Run | What it checks | Would have caught |
|---|---|---|
| `real-server.js` | Type an address, a security code from the server signs in, the arrows reach a film, it plays (its clock moves, frames decode, a frame has a picture), Back works, Change server | Sign-in by address and code, the player |
| `real-server.js`, `WMC_PAIR=1` | The same, signed in by pairing: a code and PIN on screen, approved as from a phone | Pairing |
| `real-server.js --tv` | The same with a remote's keys alone, in TV mode, and the TV menu | TV mode |
| `p2p-real.js` home, away, revoked | Signed in at home; the address stops answering and the app finds the server peer to peer, still signed in; a device taken off the list gets nothing | Remote access that only works at home; a removed device still getting in |
| `p2p-real.js` invite | A fresh app, an invite link pasted on the connect screen | Adding a server by link |
| `add-server-real.js` (once in this branch) | Found on the network, Enter a code, Type an address, Sign in with a password | Each way of adding a server |

## Android phone and TV (`android`)

`android.py` drives a debug build on an API 34 emulator (Google APIs for the phone, Android TV for the TV) with `uiautomator` and `adb`, against the server on the runner (`10.0.2.2` from the emulator). Installing over the last release is `ci.yml`'s `android-update` job (`android/scripts/check-upgrade.sh` and `upgrade-test.sh`), which every pull request runs already, so it isn't repeated here.

| Step | What it checks | Would have caught |
|---|---|---|
| address | Enter an address, then a security code from the server: signed in | Sign-in by address and code |
| settings | Settings opens with its sections | A settings page that crashes |
| film | The film plays: the server sees this device streaming | The player |
| away | The emulator's firewall blocks the server's address; the app comes back peer to peer, still signed in, and streams the film through it | Remote access from a phone |
| game | From away, Adjustris in WittyPlay starts and the server sends this device frames (WittyPlay's own stats for the session) | WittyPlay on a phone from away: the games page refused, or the stream refused before the hello |
| link (phone) | A fresh app, still away: Join with a link or code, the invite link pasted: signed in | Adding a server by link from away |

Finding a server on the network isn't checked on Android: the emulator's network doesn't pass the server's announcements through. The desktop app's `found` run covers the server's side of it, and `DiscoveryTest` the app's.

## Running them yourself

With a server from the server repository's `scripts/smoke/server.sh` running and its run folder in `SMOKE_OUT`:

```bash
SERVER_SRC=../WittyMediaServer SMOKE_OUT=/tmp/smoke-out scripts/smoke/desktop.sh /tmp/smoke-build/bin/wittyconnect
SMOKE_OUT=/tmp/smoke-out python3 scripts/smoke/android.py android/app/build/outputs/apk/debug/app-x86_64-debug.apk [--tv] [step ...]
```

The Android script needs one emulator running (`adb devices`), and `adb root` to work on it (a Google APIs image). It turns peer to peer on in the server.
