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

**Android has run on emulators and on nothing else.** [Features](#features) has what each client does, and how far each was seen.
[Android, as of 0.2.1](#android-as-of-021) lists more of what was seen and what wasn't. Using it for the first time found real bugs that nothing before it could, so anything on that list marked as not run
should be expected to have some too.

## Platforms

| Platform | Status | Notes |
|---|---|---|
| Windows 10 and later | **Ran** | From source and as a packaged app. The setup and uninstaller ran under Wine, not yet on a real Windows. |
| macOS | **Ran** | The desktop app, packaged on a Mac (macOS 27) for Apple silicon and Intel. The Apple silicon one was opened, connected to a server and used by the owner. Its uninstaller only ran on Linux with a stand-in home folder. It's the Mac's only client: the Apple project no longer builds a Mac app of its own. |
| Linux | **Ran** | `.deb` and `.rpm` installed, opened on a virtual screen, upgraded and removed in containers. `.pacman` the same. The `.rpm` also ran on Fedora 44 in a virtual machine, and from source on Ubuntu 26.04. See [below](#freebsd-plasma-bigscreen-and-linux). |
| FreeBSD 15.1, amd64 | **Ran** | In a virtual machine, as an installed package: picture and sound seen. Needs the system's Electron from the ports tree. See [below](#freebsd-plasma-bigscreen-and-linux). |
| FreeBSD 14.4, amd64 | **Ran** | The same package, in a virtual machine: installed on a bare system, opened as far as the connect screen, upgraded and removed. No video played on it. |
| FreeBSD aarch64, i386 | **Not run** | The package is built for amd64. Those would need Electron built from ports, as FreeBSD has no package of it for them at the time of writing. |
| KDE Plasma Bigscreen | **Ran** | The real shell 6.8.2 on Fedora 44, in a virtual machine: listed in its launcher, opened from it, video and sound seen, keys through the real input stack. Never on a TV or with a real remote. See [below](#freebsd-plasma-bigscreen-and-linux). |
| Android ARM, 64-bit | **Compiled** | In the same APK, from Android 6. Not run: the emulators here are x86-64. |
| Android ARM, 32-bit | **Compiled** | In the same APK, from Android 6. Not run: see [Android's processors](#androids-processors). |
| Android x86, 64-bit | **Ran on an emulator** | In the same APK. Every emulator image used was this one, on Android 16 and Android 6. |
| Android x86, 32-bit | **Compiled** | In the same APK, from Android 6. Not run. |
| Android TV | **Ran on an emulator** | Android 16, 1080p, with arrow keys and OK only. Same APK as phones. No real TV or remote yet. |
| Google TV | **Compiled** | Not run: its emulator images come under a licence that hasn't been accepted. It should behave as Android TV does, but nobody has seen it. |
| Fire TV | **Compiled** | Not run: no image for it here. Needs Fire OS 6 or later: the first Fire TV Sticks are too old for Compose. |
| Android phones | **Ran on an emulator** | Android 16 in full, and Android 6 (API 23, the oldest it supports) for connecting, playing and a network drop. No real phone yet. |
| Android tablets | **Ran on an emulator** | Android 16, 2560×1600, sideways: signing in, Home, a library, an item, and the server's pages. They use the phone's screens with wider margins. |
| Apple TV | **Compiled** | By Xcode 27 on macOS 27, unsigned, for the device and the simulator. Never run. [The first check](OWNER-STEPS.md#step-3-try-apple-needs-a-mac) is one script. |
| iPhone | **Ran in the simulator** | iPhone 17, iOS 27: connected by address, signed in with a password, Home, a library, an item page, and a film played. Never on a real iPhone. |
| iPad | **Compiled** | The same app as the iPhone, with the tablet's wider margins and cards. |
| Apple Vision Pro | **Compiled** | The iPhone and iPad app, built for visionOS 2 and later as an app of its own, with the iPad's layout: the floating bar, the server's pages in a web view, and picture in picture. Never run, not even in the simulator. |
| Apple Watch | **Not started** | watchOS has no web view and no player like the others', so it would be a different app, such as a remote. |
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
| `npm run test:real`, with `--tv` and on the desktop | 11 of 11 on the code here, and 8 of 8 on a build before its last merges | Not used: the same journey was done with real keys and pictures | 11 of 11, and 8 of 8, on a build before its last merges |
| The clock moves and frames decode | Yes, and the VM's own screen showed the clip across the whole display | Yes: the frame counter on the clip reached 10.8 seconds | Yes |
| Sound | Yes: the VM's sound card recorded the clip's tone at 330 Hz | Yes: 330 Hz recorded | Not checked |
| Finding servers with real packets | Found this machine's four servers, through the VM's network, on a build before its last merges | Found four | Found one |
| Security code and sign-in | Real server, with real key presses on the VM's screen | Real server | Real server |
| Leaving the player, and the menu at the top | Yes | Yes | Yes |
| Quit | Yes: no app and no sound server left running | Yes, back to the launcher | Not checked |
| Change server from the menu, signing out | Yes | Yes: no sign-in cookie left | Yes |
| Removing it | Yes: see below | `dnf remove`: the program and its launcher entry went, and the settings stayed until the command it gives was run | See below |

**Installing and removing, run for real in throwaway systems:**

- **FreeBSD 14.4 and 15.1,** in virtual machines, with `scripts/test/installers-freebsd.sh`. From a bare system with only what the package declares: it installs, and
  nothing in it is writable by everyone. The menu entry is right, and it opens as an ordinary user with its sandbox on. `pkg delete` says what's left. Then an upgrade, and
  `--uninstall`: `--dry-run` and no to both change nothing, the program alone keeps the data and says how to remove it, and both removes the app's folders. Someone else's
  files and a film beside them stayed, and a list of every path on the system was the same before and after. The package is 93 KB, with the same file on both versions.
- **Linux,** in containers, with `scripts/test/installers-linux.sh`: `.deb` on Debian 13, `.rpm` on Fedora 44 and `.pacman` on Arch. Installed, sandbox on, opened, upgraded and
  removed, with the removal message and the same list of paths before and after. An AppImage opened too.

Running this on a bare FreeBSD found that the app showed no text at all, as Electron brings no font and the VM used until then had one. The package now brings one.

**Seen only on Plasma Bigscreen:**

- It's listed in the launcher, with its icon and description, from an ordinary desktop entry.
- Opened from the launcher with no flags, it recognises the session and opens as a TV app.
- The on-screen keyboard appears for the address box, and the page moves up to make room. Arrows and Enter type into it, and its own Enter key submits the address.
- A virtual Xbox pad, made with `uinput`: as soon as the app opened it, the shell's input handler stopped turning it
  into key presses. Each press moved focus one step, and B opened the menu, so presses aren't handled twice.
- A sign-in made from the launcher is still there after restarting the app. No keyring wizard appears.

**Not seen, on any of these:**

- A real TV, a real remote, and HDMI-CEC. Key presses were real to the system, but a real remote may send other keys.
- Readability from across a real room. Body text is 18.75px at 1080p, from the server's big screen mode, which is how a TV browser looks too.
- Hardware video decoding. All of this was software, on a machine with plenty of power to spare.
- A real FreeBSD desktop. X11 was bare, with one small window manager. Wayland on FreeBSD hasn't been tried.
- Video on FreeBSD 14.4, which only got as far as the connect screen. Video on an installed `.deb` or `.pacman`.
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
| Size | About 3 MB |

**Why Android 6 is the lowest claim.** Media3, Activity, Core and Lifecycle, 23 libraries in all, need API 23 and won't build below it, so it's a
hard floor. Android's own lint reads every call against that version, and CI now runs it. It found the player's network watcher calling something from
API 24, which was caught rather than crashing, and two places that needed an annotation. All three are fixed.

**ARM older than `armeabi-v7a` isn't possible.** Android's tools dropped ARMv5 and ARMv6 in 2018, so the libraries this app depends on aren't built for them.

**Not seen:** this app running on any ARM device or any 32-bit build. Every emulator image used here is x86-64, so of the four libraries only that one has
been loaded. Android's emulators on this x86 machine don't run ARM at a usable speed. A cheap 32-bit ARM TV stick is the check that matters most.

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
[Apple, as of 0.3.1](#apple-as-of-031) for exactly what has and hasn't been checked.

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

Every client reaches everything the server does, except where this says it can't. Video has the native apps' own screens, and on Android and the Apple apps so do music, audiobooks and
podcasts. Everything else opens **the server's own page inside the app**, signed in: in a web view on Android and on iPhone and iPad, with big screen mode at 1920 wide on a TV.
Apple TV has no web view, as tvOS doesn't offer one to apps, so it has screens of its own for what it can do, and says plainly what it can't.

Checked on 2026-11-01 against a real server with every module, with made-up films, shows, music, audiobooks, podcasts, photos and a channel, and the real DVDs,
books and comics in the test media. **Ran** on the desktop is the real app under Linux on a virtual display, driven by real key events. **Emulator** is Android 16:
1080p TV with arrow keys, OK and Back, a phone and a tablet by touch. **Page** means the server's own page in the app.

| What the server does | Desktop | Android TV | Android phone, tablet | Apple TV | iPhone, iPad |
|---|---|---|---|---|---|
| Finding a server, a code, a password | Ran | Emulator | Emulator | Written | Written |
| Home, libraries, shows, item pages | Ran | Emulator | Emulator | Written | Written |
| Films and episodes, with resume | Ran: clock moved, place saved | Emulator | Emulator | Written | Written |
| Audio and subtitle tracks | Ran: French subtitles seen on the picture | Emulator (0.2.1) | Emulator (0.2.1) | Written | Written |
| Next episode | Ran: offered | Emulator (0.2.1) | Emulator (0.2.1) | Written | Written |
| Skip intro | Not seen here: no intros in this media | Emulator (0.2.1) | Emulator (0.2.1) | Written | Written |
| Search | Ran | Emulator, films and shows; everything else in the server's page | The same | Written, films and shows | Written, films and shows |
| Music: albums, artists, songs, a queue | Ran: opens and plays | Own screens, Emulator: [below](#music-audiobooks-and-podcasts-on-android) | Own screens, Emulator: [below](#music-audiobooks-and-podcasts-on-android) | Own screens, compiled: [below](#music-audiobooks-and-podcasts-on-apple) | Own screens, Simulator: [below](#music-audiobooks-and-podcasts-on-apple) |
| Playlists, lyrics, a song's radio, following a podcast | Ran: opens | Page, behind More. Its sound stops when you leave it | The same | Not available | Page, behind More, written |
| Audiobooks, podcasts | Ran: clock moved | Own screens, Emulator: place saved, Resume, speed | Own screens, Emulator: the same | Own screens, compiled | Own screens, Simulator: place saved, Resume, speed, with music standing in for a book |
| Radio | Page opens. No station played: none set up | The same | The same | **Not available**: says so. Could be built | Page, written |
| Books, comics, PDF | Ran: reader opens | Page: reader opens, Back leaves it | Page: reader opens | **Not available**: no web view to read in, and it says so | Page, written |
| Photos | Ran: grid and viewer | Page: viewer with arrows, OK and Back | Page: viewer by touch, Back closes it | Own screen, written: left and right through a library | Page, written |
| DVDs | Ran: the film plays | Page: the film plays, and the menu seen | Page: the film plays | **Not available**: discs need a player of their own, and it says so | Page, written |
| Blu-ray, audio CDs | Not in this test server | Not in this test server | Not in this test server | **Not available**, as DVDs | Page, written |
| TV guide | Ran: the page, with arrows | Page, on the top bar, by arrows and by controller: the grid, what's on, Back | Page: opened, upright and on its side | Own screen, written: each channel with what's on now and next, in the colours of the account's WittyTV theme. It isn't the grid: a theme's layout, type and preview don't come across | Page, written |
| Watching a channel | Ran: a channel plays | Page: plays. Arrows, channel buttons and a controller change channel, OK shows what's on, Back returns to the guide | Page: a channel plays by touch | Own screen, written: up and down change channel, with what's on shown over the picture. Its requests were checked against the real server with `curl` | Page, written |
| On TV now, on Home | Ran: the server's own row | A row of the app's own | A row of the app's own | A row of the app's own, written | A row of the app's own, written |
| Tuners, recordings | Page opens. No tuner here | The same | The same | Tuner channels listed, written. Recordings **not available** | Page, written |
| Home videos | Page opens | Page opens | Page opens | Written | Written |
| Collections | Page opens, none made | Page opens | Page opens | **Not available**: their titles still appear in libraries | Page, written |
| Games in the page | Page opens. **No game played**: no core installed in the test server | The same | The same | **Own screens and player**: the library as couch mode, a game's page, and the server's stream in a native player with controllers, profiles, the game menu and the server's saves. Simulator, through a stand-in, as the local server's runner can't start a game on this Mac: see [WITTYPLAY-APPLE-TV.md](WITTYPLAY-APPLE-TV.md) | Page, written |
| Games on someone's own PC | See [below](#games-on-someones-own-pc) | See below | See below | See below | See below |
| Settings: libraries, profiles, modules, backup, logs and the rest | Ran: every page opened with no errors | Page opens | Page opens | **Not available**: use a phone or computer | Page, written |
| Uploading from the device | Written: it opens the system's picker, not run here so as not to open a window | Written | Emulator: the picker opens, and Back returns to the page. No file sent | No | Written, the system's own |
| Downloading to the device | Written | Written | Emulator: a book saved to Downloads | No | Written: saved where Files can see it |
| Going full screen | Ran | The page already fills the screen | Emulator: in and out, and Back leaves it first | The system's player | Written |
| The server's themes | Ran, with light, paper and high contrast looked at | Colours of the server's theme, seen in light and dark | The same | Colours of the server's theme | Colours of the server's theme |
| WittyTV's themes | Ran: all nine in big screen mode with arrow keys, and as a window | Page: all nine at 1920 with a virtual controller: first focus, into the grid, no sideways page, and pictures looked at | Page: all nine upright on a phone, three on their side, no sideways page, and pictures looked at. Tablet not repeated | Colours only, written. The account's choice and its changed colours, which WittyKit's tests hold to the server's own code. The app theme's suggestion isn't read | Page follows them, written |
| A long name for the server | Ran: 40 letters wrap in the side menu | Seen | Seen | Written | Written |
| Own log, with errors reported to the server | The log's logic ran in tests | Written and shown in the app | Written and shown in the app | The log's logic ran in tests on Linux | As Apple TV |

### Music, audiobooks and podcasts on Android

A player of the app's own, on Media3 with a `MediaSessionService`. It carries on whichever screens are up, and `net/ServerPages.kt` decides what opens in it. Seen on 2026-11-01 on the
Android 16 phone and 1080p TV emulators, against a real server with `saveMetadata=0`, reading the system's own clock with `dumpsys media_session`. The TV ran the shrunk build, the phone the debug one:

| What | Phone | TV, by arrows, OK and Back |
|---|---|---|
| Albums, artists or authors, songs, a podcast's episodes | Seen | Seen, with first focus and focus returning. Songs and a podcast by touch only |
| Screen off | Clock moved, and the next track started by itself | Clock moved, and the place reached the server while asleep |
| Leaving with Home | Clock moved | Clock moved |
| Swiping the app away | Clock moved, and the service stayed in the foreground | There's no swiping away on a TV |
| The system's controls | On the lock screen and in the shade, with cover, Pause, Previous and Next. Books get Back 15 and Forward 30, and those two were pressed. Tapping the card opens the player | The launcher's card, with title and app. Its Stop pauses. **Its Open doesn't work:** see below |
| Media keys | Pause and play | Play, pause and next, from the launcher |
| Mini player over the app's own screens | Over tabs, lists and pages, in dark and light. The colour under the system's bar was then corrected, and seen again in dark only | Over lists, reached with Down |
| Queue: add, jump, change, remove, clear, shuffle, repeat | Add, remove, clear and repeat pressed, and the Change buttons seen. Shuffle pressed, with its order not looked at. Moving and jumping weren't pressed | Walked to with arrows, and the list stays put past either end. Nothing changed from there |
| A book's place saved with `/items/{id}/progress`, every 10 seconds and on pausing, leaving and signing out | Read back from the server | Read back while asleep |
| Resume, the chapter last left in the middle | Seen, after stopping the app | Seen |
| Speed, −15, +30 | On screen, not pressed. Back 15 and Forward 30 pressed on the system's card | Speed and −15 pressed |
| A song the server converts (WMA): plays, seeks, moves on | Seen | Plays and seeks by arrows |
| The network dropping, then coming back | Carried on from the same time by itself | Not tried |
| A film starting | Sound paused at once, and place saved | Not tried: the same code |
| Signing out | Sound and notification gone, final place saved first | Not tried: the same code |

**Android 6, debug build:** a book played with the screen off and after leaving, right through to the end of a chapter, which the server then marked as finished. The notification had the cover and Back 15, Pause and Forward 30, and the service stayed in the foreground. Nothing else was repeated there.

**Not seen:** any real device, and so no sound was heard: emulators have none. Android 7 to 15, headphones or Bluetooth buttons, a phone call taking the sound, TalkBack speaking, deep idle (not available on this image), the whole-screen player in the light theme, a long queue, and audio CDs, whose tracks go through the same `/playback` as other sound.

**Limits:**

- **On the TV emulator, the launcher's Open on the now-playing card does nothing.** The log says Android blocks the launch, as the launcher's service that sends it isn't on screen. Asking for it to be allowed from the app's side made no difference, so that was taken out again. Opening the app normally gets to the same place. Whether real TVs do the same isn't known.
- **The queue is kept while the app's process lives.** If the system ends a paused player, the queue is gone. Books and podcasts keep their place on the server, and Continue listening has them.
- **Sound in the server's page,** behind More, is a separate player. A page that plays a film, a channel or a game pauses the app's player, but nothing tells it about music in a page, so both could play at once until one is paused.
- **Radio** stays in the server's page, with its limits.
- **A song adds to the yearly summary, with `/view`, instead of saving a place,** as on the web, because the server starts songs over. Only books and podcasts have a place to read back.
- **Pressing Add to queue with nothing playing starts it,** as there's nothing for it to wait for.

**Limits of the server's page inside the Android and iPhone apps:**

- **Sound stops when you leave its page,** and with it the player on the lock screen. It's the web view playing, so leaving that screen ends it, and nothing
  tells the system that sound is playing. Staying on the page with the screen off hasn't been tried. On Android this now only applies to what's behind More.
- **A web view older than version 87 can't show these pages,** and says so. Android 6 comes with version 44 and needs an update of Android System WebView.
  Films and shows still play there. Versions just above that line haven't been tried: this was seen on 143.
- **What a page builds itself to save can't be downloaded,** such as a backup or a zipped log. It says to use a browser. A file the server sends by address can be.
- **Uploading by remote on a TV:** whether a TV has a file picker at all differs by device. It says so if it hasn't.
- **Remote and controller:** only emulated key presses and virtual controllers have reached the pages on a TV. See [Controllers](#controllers).

### Music, audiobooks and podcasts on Apple

The same screens and player as Android's, in SwiftUI on one `AVPlayer` (`apple/App/Listening.swift`), on iPhone, iPad, Apple Vision Pro and Apple TV. Seen on 2026-11-04
in the iOS 27 simulator on an iPhone 18 Pro, against a real server with two made-up albums of MP3s. It has no audiobook or podcast library, so a build with a
temporary switch treated music as books, and another forced the server to convert every song. Neither switch is in the code. Apple TV and Apple Vision Pro
were compiled, for the simulator and for devices, and not run.

| What | iPhone simulator |
|---|---|
| A library's albums and an album's page | Seen. Artists, Songs and More weren't opened |
| Play, a track's row, the mini player above the pill, the whole-screen player upright and sideways | Seen |
| Next, a seek on the bar, the next track by itself, the end of the queue, Play starting it again | Seen |
| Queue: Change, move, remove | Seen. Add, Shuffle, Repeat and Clear weren't pressed |
| Screen locked | Carried on to the next track. The system's now-playing service had title, artist, album, cover (768 × 768), queue place and the commands: books get Back 15 and Forward 30, songs Previous and Next. **The simulator draws no player on its lock screen,** so none was seen |
| A song the server converts | Plays, seeks by asking for a new stream from that time (`timeOffsetSec`), and moves on at its end |
| A book's place on pausing, and at the end of a part | Read back from the server: 5.5 seconds in, and the part before marked finished |
| Resume, Start over, a part's "0:05 in" and "Finished", speed | Seen. Resume asked for the part from 5.5 seconds. Speed went to 1.25× |

**Not seen:** any real device, and so no sound heard, nothing on a lock screen or in Control Center, no headphone or media keys, no phone call, no AirPlay or CarPlay.
Nor the network dropping and coming back, a film pausing the music, signing out while playing, VoiceOver, an iPad, Apple Vision Pro or Apple TV running.

**Limits:**

- **The queue is kept while the app runs.** If the system ends it, the queue is gone. Books and podcasts keep their place on the server.
- **One track after another, not gapless:** the next track is asked for when the last one ends.
- **Sound in the server's page,** behind More, is a separate player, as on Android.

## Controllers

The app has to let a controller through, and what each button then does is the same on every client: D-pad or left stick to move, the confirm button to choose, the back button to go back.

| | Xbox | DualSense | DualShock 4 | Nintendo Switch Pro |
|---|---|---|---|---|
| Android TV, this app's own screens | Emulator | Emulator | Emulator | Emulator |
| Android TV, the server's page | Emulator | Emulator | Emulator | Emulator |
| Android TV, this app's own player | Not repeated | Emulator: play and pause, skip, leave | Not repeated | Not repeated |
| Android phone, tablet | Not run: the same code as TV | Not run | Not run | Not run |
| Desktop | Ran once: a virtual pad on Plasma Bigscreen, as a key press each. See below | The page's own tests only | The page's own tests only | The page's own tests only |
| Apple TV | Written: the system's focus engine moves for any controller it knows, and nothing in this app stands in the way | As Xbox | As Xbox | As Xbox |
| iPhone, iPad | Not available on this app's own screens: iOS doesn't move focus for a controller. In the server's page, written | As Xbox | As Xbox | As Xbox |

**How Android was run.** Android's own `uinput` tool made a device with the real maker and product numbers on the TV emulator, so its real layout files and input system decided what each press meant, on Android 16. Nothing real was held in a hand.

- **Own screens and the page:** D-pad as a hat and left stick to move, confirm and back. In the page, the D-pad and buttons of all four.
- **A Nintendo pad's labels are obeyed, on an assumption.** Android names buttons by where they sit, and Linux's driver reports A as the right-hand button, so this app and the page both read A as confirm. On an older device whose driver differs, A and B could be the wrong way round. A real pad on a cheap stick is what would tell.
- **The DualShock 4 ran on the layout for the older driver,** as this tool can't set the version a newer one reports. The newer layout is the DualSense's.
- **The first press in a newly opened page counts.** A web view hides a controller from a page until a button is pressed, and the first press after opening a page didn't even do that, so A on the guide's first button did nothing the first time. The app now presses the left stick for the page when it loads, until the page can see the controller. On a TV it does this for any controller plugged in, and on a phone only if a controller was what opened the page. Seen on the TV emulator.

**Found by running it:** a DualSense gets no named layout from Android's web view, and the page looked for its D-pad in the wrong place, so it did nothing there. B at the top of a page did nothing either, as a web view keeps a controller's buttons for the page. Both are fixed.

**Not seen:** any real controller, Bluetooth, a game played with one in a web view, the Gamepad API in iOS's web view, and a Guide button on a real remote. The emulator's system took that key before this app got it.

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
view, once it had started, as far as its list: no PC was added. The server's light theme, on Home and Profile, with dark system icons and
readable text. Back during the countdown, which leaves as Cancel does.

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
- **Foldables, gesture navigation** (three buttons were on), very large text, Google TV and Fire TV.
- **A game controller,** Moonlight, and playing a game on a PC: no part of it reached a real PC.
- Two-factor accounts, and a server that has moved to a new address.
- **Hardware decoders.** The emulator's are software or its own.

## Apple, as of 0.3.1

**Run, on Linux with Swift 6.1 in a container:** every test in `apple/WittyKit` with `swift test`, including real connections to a
stand-in server: redirects not followed, oversized answers dropped, version and revision checks, and cancelling. Signatures can't be
verified on Linux, as it has no CryptoKit. Every answer is refused there, and those tests only run on Apple platforms.

**Only checked for syntax:** every file in `apple/App` and `apple/TopShelf`, with `swiftc -parse`. Before 0.3.0 the app's own files were also
type-checked against small stand-ins written for SwiftUI, AVFoundation and the rest, for each of the three platforms. That wasn't repeated for what
0.3.0 added: the server's pages on iPhone and iPad, and Apple TV's screens in `TvViews.swift`. Expect those to need the most fixing.

`apple/scripts/check-on-mac.sh` is the first real check: see [the steps](OWNER-STEPS.md#step-3-try-apple-needs-a-mac).

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
| The server's pages, iPhone and iPad | **Written** | Whether the sign-in cookie reaches them, saving a file, and whether the page's own bars sit well under the system's |
| Music, audiobooks and podcasts | **Simulator**, iPhone | A real device's lock screen, Control Center, headphones and calls, and Apple TV's focus through the lists and the queue |
| Photos and channels on Apple TV | **Written** | Whether up and down reach a player that isn't the system's |

**Known limits:**

- The server's growing streams start the player's clock at the place they start from, so the system's seek bar shows time from there,
  not the film's own time. It can only seek within what exists so far. Going further needs a track change or a new start.
- A film's now-playing information comes from the system's player. Music, audiobooks and podcasts write their own.
- Posters are kept in memory, not on disk, so they're fetched again each time the app starts.
- The hero is one picture from the server's featured list, and doesn't turn or page.
- Search in the app's own screen finds films and shows, not episodes or music. On iPhone and iPad, the server's page finds the rest.
- Apple TV's older album list (`AlbumView`) reads the first 500 items of a library. Nothing opens it now: albums open the listening screens.
- A two-factor prompt on password sign-in isn't built. Those accounts can sign in by code.
- Apple TV's guide has WittyTV's colours and the owner's own channel logos, not its themes' layouts, type or preview, nor logos from the logo service. An app theme that suggests a WittyTV theme is only followed in the page.
- There are no tests of the screens themselves. Anything that can be tested without one is in WittyKit.

## Not done yet in the native apps

- A prompt for two-factor codes on password sign-in. Those accounts can use code sign-in instead.
- On Android: picture in picture and playing a film in the background, a choice between a file's several pictures, and a baseline profile
  for faster starts. Live channels play, in the server's page. Music, audiobooks and podcasts have [their own player](#music-audiobooks-and-podcasts-on-android).
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
- **Linux** on a real computer. It ran in containers and virtual machines.
- **macOS** beyond opening it and using it with a server: not the uninstaller, the firewall's question, or an Intel Mac.
- **The network search with real sockets** on this version: it would ask the Windows firewall.
- The package check failing as it should when the package is changed.
- A server asking for a client certificate, which needs one in the system's store.
- Installers on a real Windows, and very low-end hardware.
- Screen readers. Roles, labels and live regions are checked as they appear in the page, but no screen reader has read them.
- Everything marked as not seen in [Features](#features). They are the web interface's own features, displayed unchanged.
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
