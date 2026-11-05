# Changelog

What changed in WittyMediaClient, newest first. What changed before it had a repository of its own is in the
[WittyMediaServer changelog](https://github.com/wittywilla/WittyMediaServer/blob/master/CHANGELOG.md).

## Unreleased

- **Apple: music, audiobooks and podcasts have a player of their own, as on Android.** On iPhone, iPad, Apple Vision Pro and Apple TV: albums, artists or authors,
  songs and podcast episodes have the app's own screens, with a queue you can add to, rearrange and shuffle, and a mini player above the bar. Sound carries on
  with the screen off and after leaving the app, with the player on the lock screen and in Control Center, and headphone and media keys work. Books and
  podcasts save their place and resume it, go back 15 and forward 30 seconds, and keep a chosen speed. A song the server converts seeks like any other, and it
  tries again by itself when the network comes back. Playlists, lyrics and following a podcast are behind More, in the server's own page.
- **Apple: the iPhone and iPad app looks and works like the Android app.** The same filled buttons with the main one in the accent colour, outlined fields,
  posters with their titles under them, and Android's spacing and type. Home, Search and Profile are in the same floating bar on iPhone, iPad and Apple Vision Pro,
  and music is reached from Home's library pills. Home has the posters to swipe through with Play; items and shows have their picture behind them, with season
  pills and episode rows. Profile has the licences and this app's log, as on Android. A sign-in is kept between runs, and Home no longer says it lost the
  server the first time it opens.
- **Mac: the desktop app is the Mac's client.** The Apple project no longer builds a separate Mac app, which looked and worked differently from the others.
- **Apple Vision Pro:** the iPhone and iPad app also builds for visionOS 2 and later, as an app of its own rather than the iPad one in a window. It takes the iPad's layout,
  opens the server's pages inside the app, and reports its errors as visionOS. Compiled, never run. CI builds it where the Mac runner's Xcode has the visionOS SDK.
- **Android 0.3.0: music, audiobooks and podcasts have a player of their own.** Sound carries on with the screen off, after leaving the app and after swiping it away, with the
  player on the lock screen, in the system's controls and on a TV's home screen, and headphone and media keys work. Albums, artists or authors, songs and podcast episodes have the app's own screens,
  with a queue you can add to, rearrange and shuffle, and a mini player over the rest of the app. Books and podcasts save their place and resume it, go back 15 and forward 30 seconds, and keep a
  chosen speed. A song the server has to convert seeks like any other. It tries again by itself when the network comes back, and everything works with arrows and OK on a TV. Playlists, lyrics
  and following a podcast are behind More, in the server's own page.
- **Android: nothing the server does is a dead end now.** Music, audiobooks, podcasts, radio, books, comics, photos, disc menus, games, the TV guide, collections
  and settings open in the server's own page inside the app, signed in, instead of "open it in a web browser". On a TV it's the big screen version, and Back
  closes what's open on the page first. A page can go full screen, choose a file to upload, and save a file to Downloads. A device whose web view is too old says so.
- **Android: a better look.** A row of songs shows each album once. Long titles get two lines. Item and show pages have a picture behind them, and episodes one of their own,
  with how far through they are. On a TV the server list sits beside its heading rather than scrolling it away. On a phone, what scrolls under the clock fades out, and on
  its side, rows run to the edge rather than stop short of the camera. Profile says who's signed in.
- **Apple: the same, not yet compiled.** On iPhone and iPad everything else opens in the server's page. Apple TV has no web view, so it gets screens for music, photos and
  live channels, and says plainly what it can't show. The apps are now called WittyMediaClient. `apple/scripts/check-on-mac.sh` is the first check on a Mac.
- **Android TV:** Back from the code screen puts focus on the server that was chosen, not the first in the list, so OK can't open a different server by mistake ([#7](https://github.com/wittywilla/WittyMediaClient/issues/7)).
- **WittyTV on Android:** TV guide is on the TV's top bar, and Home has a row of what's on now, on phones too. Channel buttons, arrows and a controller change channel. A remote's Guide button opens the guide, though no emulator has passed that button on yet.
- **WittyTV on Apple TV, not yet compiled:** the guide and the channel banner take the colours of the WittyTV theme chosen on the account, from any device, and show the owner's channel logos.
- **WittyTV on Apple, not yet compiled:** Apple TV has a guide with what's on now and next, and a player where up and down change channel, with what's on shown over the picture. Home has the row too. iPhone and iPad have the server's guide.
- **Controllers on Android:** the first press on a page opened with a controller now counts. It used to do nothing, so opening the TV guide took A twice to watch.
- **Controllers on Android:** Xbox, DualSense, DualShock 4 and Switch Pro layouts all move and choose, on the app's own screens and in the server's page. A Nintendo pad's A is confirm, as printed. B now leaves a server page when there's nothing left to go back through.
- **Desktop 0.2.4:** a server that was used before and is also found on the network is listed once, under On your network, instead of twice ([#9](https://github.com/wittywilla/WittyMediaClient/issues/9)).
- **Desktop:** what has its own Back on a TV is read from the server's page, with the old list for older servers, so the two can't drift apart.
- **Desktop on a Mac:** the window has the system's red, yellow and green buttons at the left of the title bar, rather than Windows-style ones
  at the right, and the title sits in the middle. A double-click on the bar does what System Settings say. There's a Mac menu bar, so
  Command-Q, copy and paste work, with Help and Change server in it. Windows, Linux, FreeBSD and TV mode are as they were.
- **Desktop: the connect screen looks like the other apps' sign-in.** The glow at the top, the WittyMediaServer mark and name,
  servers as cards with "Last used", a field whose label rises onto its outline, six code boxes over a number pad, and a
  plain warning for a server that has changed. A new server can also be signed in from a phone: the screen shows a code and
  a QR code, and someone already signed in approves it. On a TV the words sit on the left and the choices on the right, sized
  for the room. Keyboard first throughout; Reduce Motion stops the spinners, and forced colours keep the QR code readable.
- `docs/PLATFORMS.md` now has what every server feature does on every client, and how far each was seen.

- The desktop app is now called WittyMediaClient everywhere: `WittyMediaClient.exe` on Windows, `WittyMediaClient.app` on macOS
  and the `wittymediaclient` command and package on Linux. Its data folder is named the same.
- Windows gets a normal setup wizard: for one person or for everyone, in the folder you choose, with shortcuts and an entry in
  Add or Remove Programs. It upgrades in place and has `/S` for scripts.
- The Windows uninstaller removes exactly what was installed, and asks whether to delete your settings, saved sign-ins, logs and
  caches too. Silently it keeps them, unless given `/RemoveData`. Something of your own in the program's folder stays.
- macOS gets a `.dmg` and a `.zip`, with an uninstaller that lists what it would remove from your Library and asks first.
- Linux gets an `.rpm` beside the AppImage and `.deb`. The packages now declare every library the app needs, remove everything
  of theirs from the system, and say what's left in your home folder and how to remove it.
- The portable Windows `.exe` is gone: it couldn't be uninstalled, and the setup needs no administrator for one person.
- The program can't be run as a bare Node interpreter or be given Node options, and nothing it installs is writable by everyone.
- WittyMediaClient is now a project of its own, developed and released from this repository.

### Desktop app 0.2.2

**New systems**
- **FreeBSD:** a package of its own, on the system's Electron from the ports tree, with a font, as a bare system has none. `wittymediaclient --uninstall` asks about the program and your settings separately, removes only what's the app's, and says what's left.
- **KDE Plasma Bigscreen:** the Linux app appears in its launcher and opens as a TV app by itself. It has been run in the real shell, in a virtual machine.
- `--tv` and `--no-tv` ask for that anywhere else, or turn it off.
- Linux gets a `.pacman` package too, for Arch and its relatives.

**On a TV**
- The whole screen, no title bar, and the server's big screen mode.
- Back works with a remote that calls it Escape, as HDMI-CEC remotes do.
- Back at the top of the app opens a menu, for Change server and Quit, which a remote had no way to reach.
- The on-screen keyboard works on Wayland, so an address can be typed with a remote.
- No keyring wizard over the app when signing in.

**Everywhere**
- Back can't walk out of a server's first page to the connect screen any more.
- The app has an icon. It had Electron's until now.
- `npm run test:real` runs the real app against a real server with key presses alone, and plays a video.

### Android app 0.2.1

**The first version made into an APK and used.** On emulators only, against a real server: Android 16 as a phone and as a TV, and
Android 6, the oldest it supports. [What was and wasn't seen](docs/PLATFORMS.md#android-as-of-021). Everything below was found that way.

**On a TV**
- Search and Profile can be used with a remote. Nothing had focus on them, so the next press landed on Home and OK left again.
- Profile no longer opens with Sign out highlighted.
- The security code and the TV sign-in fit on the screen, side by side. They used to scroll their own instructions out of sight, among
  them the address to open.
- Left and right stay within a row. Pressing past the end jumped to whatever was up and to the side.
- Skip intro comes up by itself, and OK takes it. It only existed among the controls, which have hidden by the time an intro starts.
- Closing a list of tracks goes back to the button that opened it.
- Licences and the log scroll with a remote. They never did, whatever the code said.
- The focus ring no longer runs through a card's title.

**On a phone**
- The status bar can be read, as its icons were dark on a dark page, and three-button navigation has no white bar across the screen.
- The poster at the top of Home sits in the middle, and turned on its side a phone gets the wide picture with its title and Play beside it.
- Three posters across rather than two, and a poster on an item's page.
- The keys on the number pad stay still when a message appears or goes.

**Everywhere**
- The app is called WittyMediaClient.
- The progress bar on a card can be seen. It had no height.
- A server only leaves the list after 45 seconds of being gone, and servers of the same name keep their order. Rows used to disappear
  and take focus with them each time Android reported one lost.
- The security code screen says which server it's for.
- After the next episode starts, Back goes to that episode, not the one just finished. Back during the countdown leaves, as Cancel does.
- Next up says which episode. Profile's Switch profile is now Sign out, which is what it does. Text subtitles don't list their file format.
- The web view shows it's working while it starts, which takes seconds the first time and used to be a black screen.
- Android 6 hears a network coming back. The call used before starts at Android 7, so it silently never did.
- The build names its build tools, and lint is clean of errors, so a build can't look for a version that isn't installed.

**Processors**
- One APK names all four processors, 32-bit ARM and x86 included, and CI fails if a native library is missing for one.
- Android's own lint now runs in CI, which is what lets the app claim Android 6.

### Android app 0.2.0

Compiled against Android's own classes, and its logic and network calls tested. It wasn't made into an APK or run: 0.2.1 was.

**Security**
- Nothing leaves by device-to-device transfer now: `allowBackup=false` doesn't stop that on Android 12 and later.
- A sign-in is sealed together with the key of the server it belongs to.
- A password or code goes out only after the server has just proved it's the one the person was shown.
- A bare number such as `134744072` no longer counts as a local name, and a local name that resolves to the internet is refused.
- A server's answer can't point the player at another machine.
- The web player's stored data goes with the sign-in, and its page crashing no longer takes the app down.
- Pictures from a server are cleared on leaving it.

**Playback**
- Leaving the app pauses and saves. It used to carry on playing behind Home.
- Other apps' sound, phone calls and unplugged headphones are respected, and the screen stays on.
- The server hears what this device really plays. A file it can't decode is converted and tried again.
- A dropped network, a busy server or an expired stream recover by themselves, and failures are in plain words with Try again.
- A seek bar that works with a remote. Watch next, Next episode, Info on how it's playing, Show in 2D, and sound and radio items.
- The system's now-playing card and media keys.

**Screens**
- Home has library tabs, a hero with Play, and Search and Profile: a floating bar on a phone, along the top on a TV.
- Licences and this app's log, in Profile. A QR code on TV sign-in.
- Focus goes back where it was after Back, and screens show what they had while asking again.
- Sizes and type from the server's design tokens, with ten-foot sizes on a TV. Room is left for the system bars.
- TalkBack hears roles, states and errors as they appear. Errors aren't marked by colour alone.

### Desktop app 0.2.0

**Security**

- A code or a "trust this server" only goes to the key the person was looking at. If the server's key changes while the
  screen is open, nothing is sent, and the screen comes back with the new fingerprint and says why.
- A sign-in stays with the server it was made with. Another server turning up at the same address gets none, even one
  this app remembers.
- **Change server now signs out**, on this computer and on the server, as it does on Android. Going back means signing
  in again.
- The app's own pages have a scheme of their own instead of `file://`, so no file on disk or on a network share can pass
  for the connect screen. A server's page can't open it either.
- Packaged apps no longer run as plain Node, take Node's options or debugging flags, or load code from outside their
  package. On Windows the package's contents are checked against the program, and the sign-in cookie is encrypted with
  the system's own key (on Linux, where a keyring is running).
- A hostile server's page can't bury the screen in browser windows or save dialogs. Redirects never open a browser, a
  download has to come from the open server, and only that server's page gets the Moonlight and title bar messages.
- A server asking for a client certificate gets none. Before, Electron gave it the first one it found.
- Answers from a server that hasn't proved itself are limited in size and checked part by part, and names and messages
  from it are cleaned before they are kept or shown.
- `state.json` is now written whole or not at all, and on Linux only this user can read it.
- Announcements on the network can't point the app at this computer itself.
- Nothing can fetch spell-checking dictionaries from a third party.

**Things that were broken**

- Valid JSON with the wrong things in `state.json`, such as a window size that isn't a number, stopped the app from
  starting. What can't be used is now dropped.
- A server that moved to another server's old address was reported as a look-alike even though its key was remembered.
- A rejected page load counted as a crash in the log. A failed save or an odd answer to a code could leave the number pad
  dead. A crashed page left a dead window, and a crashed title bar left one with no way to close it: both recover now.
- A bad certificate said "can't reach a server". It now says the certificate can't be trusted. Moonlight is found on
  Windows installed on any drive. The title bar goes back to the app's colours after leaving a server, and a saved window
  size is the normal one rather than the maximized one.

**Keyboard and screen readers**

- **F6 moves between the page and the title bar**, which the keyboard could never reach before. Left, right, Home and End
  move along it, Escape goes back. Help lists the key.
- The title bar's buttons have drawn icons rather than text characters, and the maximize button shows when it restores.
- The connect screen has a visible Back on every screen, and says "Connecting…" with a way out when a server is slow.
  Back returns focus to where it was. Modifier keys no longer type digits.
- Screen readers hear which screen they are on and how many digits are in, rather than the whole page again on each
  change. Roles and labels now also work on older TV browsers, and errors are tied to the address field.
- The connect screen now uses the server's design tokens: its type, spacing, corners and control heights, with its hover,
  disabled and focus states. It respects reduced motion, high contrast and forced colours, and the number pad fits the
  window without scrolling.
- `npm run test:app` drives the real app against a stand-in server.

**Updated:** Electron 45.2.1.
### Apple apps 0.2.0

**None of the screens here have been compiled or run:** that needs a Mac. WittyKit's rules are tested on Linux, and the
rest has been read and syntax-checked. See [what has been checked](docs/PLATFORMS.md#apple-as-of-020).

**New look and places**

- iPhone has a floating pill along the bottom with Home, Music, Search and Profile. iPad and Mac have a sidebar with the
  libraries in it. Apple TV has the system's top tabs.
- Home has the libraries as tabs along the top, a big picture with a Play or Resume button, and rounded cards with a bar
  showing how far through something is. Sizes, spacing and corners come from a small file mirroring the server's tokens.
- Search for films and shows.
- Libraries these apps can't open yet are listed, with a plain note that they play in a browser for now.
- Items with no picture get a plain card, and every page says something when it's empty.

**Apple TV**

- A Top Shelf: continue watching and recently added at the top of the Home screen. It needs the owner's signing team, and
  is simply empty without it.
- The sign-in screen shows a QR code for a phone's camera, with the address and code still written out.
- The film's frame rate and dynamic range are asked of the TV. Back no longer quits from the middle of signing in, focus has a
  first place to land and returns to where it was, and a disabled button can't take the focus away.

**Playing**

- The app says what the device can really do: HEVC, AV1, HDR and sound channels. Phones and tablets no longer take a
  TV's limits, and on a metered connection they ask for a lower bitrate.
- Sound plays with the silent switch on, and carries on after a phone call when the system says to. iPhone and iPad offer
  picture in picture. Lock screen, Control Center and Apple TV's info panel show the title and poster.
- A stream starts from the right place, as the seek now waits until it's ready. Switching tracks can't save a wrong
  position, sound tracks inside a file can now be switched, and the right language is chosen: "eng" and "en" were never
  matched, and it fell back to the first track.
- Leaving while a stream was being asked for could start it playing with no screen, and the server's conversion was left running
  when a stream was replaced. Neither happens now.
- A failed stream retries a few times and then says so, with Try again and Back: it used to be able to retry for ever, and
  on Apple TV the error had no way out. A stall longer than 30 seconds counts as a failure, and it recovers by itself when the
  network comes back.
- Going to the background saves the place and pauses. A finished film is saved as finished. The next episode's button appears
  in the last 30 seconds.

**Security**

- A code or a password only goes to the key the person was shown. If another key answers, nothing is sent and the warning
  shows the new one.
- The key a sign-in belongs to is kept with it in the Keychain, so rewriting the app's plain settings can't point the token at
  another server. A failure to save is noticed and said, rather than ignored. On a Mac it uses the modern keychain when the
  build is signed.
- Answers are read up to a limit, far smaller for an address that has proved nothing, and pictures have one too.
- Redirects to another server, port or scheme are never followed. http moving to https on the same host is tried as a new
  address and proved again from the start.
- A local name that resolves to the internet is refused for plain http. A bare number such as 134744072 no longer counts as a
  local name. Addresses in a server's answers can't lead away from that server, and neither can pictures sent with the sign-in.
- From the game page, only a link the person followed can open a browser, and plain http only goes to the local network.
  Local announcements can't point at this device, and can't make the app open unlimited connections.
- Names and messages from a server are cleaned before showing. No cookies or cached answers, and TLS 1.2 at least.

**Things that were broken**

- Following a link out of the game page closed the player, and a crashed page left a blank screen. Sign-in by code stopped for
  good on one network error, and an approval without a token left the screen waiting.
- Errors said things like "NSURLErrorDomain error -1004". They now use plain words, and leaving a screen no longer counts as
  one. Each one has an icon and the word "Problem" for screen readers, in the theme's danger colour, instead of a fixed red.
- A server updated to refuse this app was only noticed when connecting anew, not at start.
- Posters could use over 300 MB. They now stay within 64 MB, and the home page keeps showing when a refresh fails.

**Screen readers and text size**

- Labels and headings throughout, with cards read as one thing with their progress, and selected tabs announced as selected.
- Problems, search results, the digits typed and the next episode's countdown are announced.
- All text follows Dynamic Type. Reduce Motion is respected, and nothing turns by itself.
