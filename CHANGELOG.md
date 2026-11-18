# Changelog

What changed in WittyMediaClient, newest first. What changed before it had a repository of its own is in the
[WittyMediaServer changelog](https://github.com/wittywilla/WittyMediaServer/blob/master/CHANGELOG.md).

## Unreleased

- **Android TV follows the server's TV levels (WittyMediaServer #469).** A server page opens on a TV unless the server's table says it is for a computer, so game settings, controllers, collections and the like open again instead of a QR card. The card now says where to change it (the WittyMediaClient app on a Windows or Mac computer, or a web browser), with what is set now, and a QR code a phone can open. The layout editor and name and logo are made on a computer. A server without the table keeps the old behaviour.

## 0.5.2

- **Peer to peer ships in every package.** 0.5.1's Windows, macOS and Linux apps (and the Flatpak and snap) said "its
  connection helper is missing": the release never built it. Its iPhone and Apple TV apps had no peer-to-peer library,
  and the FreeBSD package never had a helper. Every release job now builds the helper or library from the server's
  source, and a release without it fails instead of shipping. On FreeBSD the helper sits beside `app.asar`, where the
  app now looks for it.
- **Choose a server, as on Apple TV, on the desktop and Android.** The new logo in the lockup; YOUR SERVERS and ON THIS
  NETWORK; round server pictures, with a blue dot and a **Peer to peer** chip for a server reached from away; and the
  **Connect from anywhere** panel, with its picture (this device, Encrypted, your server), **Join with a link or code**,
  **Show a code to type in** on the desktop (Scan a QR code and Enter an address on Android), and three promises: end to
  end encrypted, nothing opened on your router, invite only.

## 0.5.1

- The Linux snap is built and kept with the release, and no longer tried for the Snap Store (0.5.0's release stopped there).

## 0.5.0

- **Apple: every look's finish, scene and type set; the layout editor; the server-name editor.** The theme's `look` (`GET /theme`)
  now reaches every surface: glass on cards, rows, the Dock and groups, gloss on buttons and the main action, bevel on what can be
  pressed and on card pictures, glow on focus, and scanlines or paper grain, each at the level the experience asks (none, subtle,
  full) and a step lower on a modest device, in low power mode or with Reduce Transparency or Motion. The theme's scene (sky, light
  sweep, bubbles, hill) is drawn behind the page and under the menu; Reduce Motion stops it drifting. Corners are the theme's radius
  times the experience's multiple, and the type sets (system, humanist, rounded, mono, serif) use the bundled open fonts Nunito,
  Source Sans 3, Source Serif 4 and JetBrains Mono (SIL OFL, `apple/App/Fonts`, credited in NOTICE). Nothing names a look by its id.
  **You -> Edit layout** picks a part of the shell or a section of the page up (OK or Select, move with the arrows or the buttons, OK
  to drop, Back to cancel; every move is announced), for me (`/sdui/placements` and the page's own arrangement) or, for
  administrators, for everyone (`/sdui/config/experience`), with undo, redo, reset and presets. **Settings -> Server name and logo**
  (administrators) colours letters or words by theme colour, fixed colour or gradient, bold, presets, the mark and a logo, shows the
  name in every frame it appears in and warns, with the numbers, where a colour does not read. Apple TV: Home no longer lets shelf
  titles run under the top bar, and Customise has room above the Dock.
## 0.5.0

- **What goes wrong is reported to the server's log, filed where it belongs.** Pages that don't load and parts of a page
  the app doesn't know (kind `sdui`, once for each type), connections from away that fall back to a relay or drop
  (`p2p`, filed under `p2p-` and the end of this device's peer ID), karaoke's parts (`karaoke`), remote control
  (`remote`, under `rc-` and the device's id), watch parties, and a player far out of step with one (`party`, under
  `party-` and the room), and games, whose session id is set while they play (`game`). A fault that keeps happening
  is sent at most once a minute. Every app's log now also hides invite secrets, join codes, the pairing check `k=`,
  the `X-Witty-Connect` and `X-WMS-Pair-Secret` headers, SyncPlay's `member=` and Xtream logins in `/timeshift/`.
- **Desktop: From away, on and off.** **Server → Stop Connecting from Away** on a Mac (in the Help menu on Windows and
  Linux, and TV mode's menu) takes this computer off the server's list of devices that may reach it from away; reached
  from away right now, it goes back to the server list. **Connect from Away Again** puts it back. The choice is kept
  for that server. As the Apple apps' You → From away.
- **The app has its icons, and a new logo.** The family's mark is now orbitw: a ring with its own coloured dot and
  what each app is inside. This app's is a screen on a stand carrying a small ring with the W and a mint dot; a
  server's is the W in its orbit with an amber dot, so the two are told apart at a glance. iPhone and iPad have an
  icon with dark and tinted versions, Apple Vision Pro a three-layer one, and Apple TV a layered icon that moves in
  depth when focused, Top Shelf pictures (standard and wide), and a backdrop behind its sign-in screens. Android has
  launcher icons for every density, a round icon, an adaptive icon with a themed (monochrome) layer, a TV banner, a
  splash screen and the same TV backdrop; the desktop app has icons for macOS, Windows and Linux, a disk-image
  background and installer pictures. The marks inside the app are drawn from generated code, sharp at any size. All of
  it is drawn by WittyMediaServer's genicon: `scripts/sync-brand.sh` redraws it.
- **Android: from away, peer to peer.** With WittyMediaServer 0.8.0-alpha's connector built into the app
  (`android/scripts/build-wittyconnect.sh`), a phone, tablet or TV that is on its server's list reaches it from anywhere, as the Apple
  apps do: home first, then peer to peer, back home by itself. **You → From away**, invite links in the address box, and **Join from
  away** for a device that has never been home. Seen on a phone emulator with the server's address taken away: reconnected, and a film
  played through the connection.
- **Android: layout options.** The menu is drawn as the server's layout says: a sidebar or a rail down the side, tabs across the top
  (over the page in the streaming style), the phone's tab bar, Android TV's top menu, or a menu down a TV's side that opens with focus.
  **You → Layout** chooses for this device. Seen on a tablet (sidebar, top tabs) and Android TV (compact list with its side menu).
- **Android: modules' settings** under **You → Modules**, in the app's own controls; a module's pages and rows are drawn as any page.
- **Android: pairing with a QR code and a PIN, switching profile, parental controls and screen time, skip markers, canvases and Where to
  Watch**, brought in from the paused branches and built for phone, tablet and TV. The extras branch's own karaoke mixer was left out in
  favour of the merged karaoke. Unit-tested; not yet walked through on an emulator.
- **Android karaoke:** parts in any PCM format, channel count and sample rate; the app's equaliser, preamp and volume leveling apply to
  them; a slider is heard in about 0.15 s; they keep playing in the background; a TV's Now Playing has Karaoke, usable with the remote.
- **Android: pages are laid out off the main thread** (a slow TV stick could end the app); TV tabs are chosen as focus rests on them;
  card titles use the title size; an episode's still keeps its shape in its header. The release build was started on a phone, a
  tablet and Android TV.
- **Android: remote control and watch parties.** The app is a device other apps can play on and control (seen: an Android TV
  emulator took play and pause from the Remote Protocol and reported its state), and a controller with **Play on…** and a full remote;
  watch parties can be started, joined by code and kept in step. The controller and parties are unit-tested only.
- **Android: saved servers first** in the server picker, the last used first and with focus on a TV, the servers found on the
  network below them; **Show saved servers first** under **You → Servers on this device** turns it off.
- **Android: removing servers.** A server never reached since this version counts from when it first ran, as on Apple; a video's own
  picture settings and the last TV channel go with their server. On a TV the picker focuses the last-used server.
- **Apple TV and Android TV: live TV for long channel lists.** The guide shows a chosen **set** of channels: all of them,
  favourites, one source, one group of a playlist, or sets of your own made from any channels (renamed, reordered, and shared with
  everyone by an administrator), remembered on each TV. It shows 25, 50, 75 or 100 channels a page, or all of them scrolling and
  loaded as they come into view; finds a channel by name; and goes to a dialled number, offering all channels when it isn't in the
  set. **Watch from the start** plays a programme from its source's archive, and recordings can start early, end late, and for a
  series follow the title on any channel, record new episodes only and keep the newest few. On a phone or tablet the guide is the
  server's own page, which has all of this. Each part appears only when the server offers it (`tv-sets`, `tv-guide-paging`,
  `tv-catchup`, `tv-dvr-rules-2`). Unit-tested and built; not yet run on a simulator or emulator.
- **Desktop: secure pairing.** Signing this computer in by having a phone approve it now uses the server's secure
  pairing where it has it (`pair-totp`): a QR code, the code, and a 6-digit PIN that changes every 30 seconds with a
  countdown, which the person approving types. Against an older server it shows the code alone, as before.
- **Desktop: saved servers first.** The server list puts the servers this computer has used on top, the last one used
  first and with focus, and the servers found on the network below them, so nothing found pushes them out of sight. A
  switch under the list, **Show saved servers first** (on unless turned off, kept on this computer), brings back the
  old order. The same setting and wording as the Apple and Android apps.
- **Apple: signing in to a server for the first time no longer leaves Home and Search spinning.** The server's status was read before the app
  had a connection to it, so it was never asked what it can do; its pages stayed "not known yet" and the menu showed "No libraries yet".
  Opening a server now always asks. Seen on the iPhone and iPad simulators against a 0.8.0-alpha server.
- **Apple: pairing with a QR code and a PIN, profiles and parental controls, Remote Protocol, watch parties, skip markers, canvases and Where to
  Watch**, brought in from the paused branches (`wip/client-apple-pair`, `-remote`, `-media`) and built for iPhone, iPad and Apple TV. A TV or
  phone being signed in shows a QR code, its code and a PIN that changes every 30 seconds; **Sign in a TV** under You approves it, now on
  Apple TV too. On Apple, the media branch's own karaoke mixer was left out in favour of the karaoke above.
- **Apple TV: the server picker scrolls** when many servers are found, so **Manage servers** stays reachable, and it takes focus by itself
  after the server in use is removed. A server never reached is no longer counted among those "not reached for N days", as on the desktop and
  Android. **Customise** lists menu entries the profile hid by their names. Server-driven cards' titles use the title size on every device.
- **Desktop: Manage servers from the menu.** **Server → Manage Servers…** on a Mac, **Manage servers…** in the title bar's
  Help menu on Windows and Linux, and in TV mode's menu open the list of servers this computer remembers without leaving
  the one in use: it is marked **In use**, **Back to** it (or Escape) returns to it still signed in, and it can be removed
  from there too, after a question that says it signs out of it here (with the usual Undo). Undoing the removal of
  several servers now says "3 servers are back." instead of reading out every name.
- **Karaoke from a song's separate parts, on Android and Apple.** On a server with `karaoke-auto` (WittyMediaServer 0.8.0-alpha), opening
  karaoke on a song asks the server once, and the server makes a karaoke version by itself: a quick one in seconds, and a properly separated one
  behind it when its owner has a separator installed. The apps play the parts in place of the song, in step to the sample (Android: decoded and
  mixed into one output; Apple: one audio engine, every part started on the same clock tick), with one **Vocals** slider, a **Sing** button that
  takes the singer out and puts them back, and **More**: a slider for each part, **Reset**, and whether it's the **Quick version** or
  **Separated**, with **Preparing a better version…** while the better one is made, which then takes over without a press. Levels are remembered
  for each profile. Lyrics, seeking and pausing follow the song as before. If the parts can't be played the normal track plays and the screen
  says why; on an older server karaoke is as it was. On Apple TV it's in Now Playing, behind **Karaoke**. On Apple the parts follow the song's
  speed and its equaliser, preamp and volume levelling. Checked on screen on an Android phone emulator only; see [PLATFORMS.md](docs/PLATFORMS.md).
- **Apple: Home, Search, libraries and title pages are the server's own pages, on a server that has them.** With WittyMediaServer 0.8.0-alpha
  (features `sdui-pages`, `sdui-catalog`, `sdui-navigation` and `sdui-personal`), the iPhone, iPad and Apple TV apps draw the pages the server
  describes ([SDUI.md](https://github.com/wittywilla/WittyMediaServer/blob/master/docs/SDUI.md)) with their own SwiftUI views: all 25 components
  and 14 card styles, laid out from the page's own device profile, coloured from the theme and its scopes. The top menu on Apple TV and the bar,
  strip and Menu on iPhone and iPad are built from the server's navigation, so re-ordering Home, adding a page or moving a menu entry on the
  server reaches the apps with no update. **Customise** on a page reorders, hides and pins its sections and sets spacing, card sizes and the tab
  that opens first, where the page allows it. Apple TV's Top Shelf is filled from the server's own Top Shelf document. Settings is unchanged: it
  is the You screen, as before. Against an older server every screen is the hand-built one it was. WittyKit passes all 57 of the server's
  conformance fixtures (`swift test`; `apple/scripts/sync-sdui-fixtures.sh` fetches them where the server's repository isn't beside this one).
  Seen briefly in the iOS 27 and tvOS 27 simulators against a real server; [PLATFORMS.md](docs/PLATFORMS.md#server-driven-pages-on-apple) says
  exactly what was and wasn't.
- **Android: the server's own pages, on phones, tablets and Android TV.** With WittyMediaServer 0.8.0-alpha (features `sdui-pages`,
  `sdui-catalog`, `sdui-navigation`, `sdui-personal`), Home, Search, every library, a film's, show's, episode's, album's and collection's
  page, Live TV, Collections, Libraries and any page an administrator makes are the server's pages (its `docs/SDUI.md`), drawn by the app
  with its own widgets, and the menus (the floating bar, the strip and drawer; a TV's top bar) are made from the server's. Re-ordering
  Home or adding a page on the server shows in the app with no update. **Customize** on a page moves, hides and pins its sections and
  sets spacing, card sizes and the tab it opens on, for the profile, saved on the server. Pages are kept on the device, so they open at
  once and still show with the server out of reach. You and its settings are the app's own, unchanged; an artist's page, the players, the
  guide, the readers and games stay the app's own screens. Against an older server the app's own screens are used as before. On Android
  TV the home screen gets a channel and Watch Next entries from the server's shelf. The server's 57 conformance fixtures run as a unit
  test. Run on an emulator as a phone in full and as a TV in part; not as a tablet, and never on a real device:
  [PLATFORMS.md](docs/PLATFORMS.md#server-driven-pages-on-android) says exactly what was seen.
- **Removing servers a device remembers, in every app.** A server that had gone, moved or been reinstalled used to stay under
  "Used before" for good: nothing could take it off the list. Now each remembered server can be removed, and with it everything the app
  kept for it and nothing of any other server: its address, the proof of who it is, the sign-in (the server is told to end that session,
  if it can be reached within three seconds), its theme choice and other settings kept for it, its logo and cached data, and its
  peer-to-peer way from away, with this device taken off the server's list. Nothing on the server itself is deleted.
  *Desktop:* a bin beside each server (shown on hover and focus), Delete or Backspace on it, or its right-click menu; "Removed … Undo"
  for eight seconds, and only then is anything deleted or the server told. *Android phone and tablet, iPhone and iPad:* swipe, long-press
  or Edit, with Undo for six seconds. *Android TV and Apple TV:* hold Select (or Menu on Android TV) on a server, or open **Manage
  servers** under the list. On the phone and TV apps **Manage servers** is also under **You → On this device → Servers on this device**.
  **Remove all servers** and **Remove servers not reached for…** (30 days, 90 days, 6 months, 1 year) say exactly which servers will go
  and ask first; nothing is ever removed by itself. Each server says when it was last reached, and one not reached for 90 days is marked.
- **One server is one entry.** A remembered server is told by the ID and key it proved, not by its address: one that changes address, or
  is found on the network and also typed in, updates its entry instead of adding a second, and what was kept for it moves with it. A
  list that already has a server twice is merged the first time this version starts. A server reinstalled with a new identity is a
  different server to the app: the warning says so and offers **Remove the old server**.
- **Desktop: reaching your server from away, with nothing set up on its router.** With a server that has peer-to-peer connections on
  (WittyMediaServer 0.8.0-alpha, **Settings → Remote Access**), the app pairs itself while it's at home and signed in, and when it later
  can't find the server at its address it connects peer to peer by itself, still signed in. The title bar says how: direct, or through a
  relay. A device that was never at home pastes an invite link where the address goes. The connecting is done by `wittyconnect`, a helper
  built from the server's source (AGPL-3.0-or-later) that ships beside the app; it gives the app an address on this computer that only
  the app can use. **Change server** also takes the device off the server's list. Run for real on macOS against a real server, on one
  network (`test/app/p2p-real.js`); not yet across two routers, and not on Windows or Linux. Packages get the helper only when they're
  built with the server's source at hand (`npm run build:connect`); without it the app says the helper is missing. Not in the FreeBSD
  package yet.
- **Apple TV, iPhone and iPad: reaching your server from away, with nothing set up on its router.** With a server that has peer-to-peer
  connections on (WittyMediaServer 0.8.0-alpha), the app puts itself on the server's list while it's at home and signed in, and when it
  later can't find the server at its address it connects peer to peer by itself, still signed in: everything it asks, every picture,
  the video and music players and the server's own pages go through the connection. **You → From away** says how the server is being
  reached (at home, direct, or through a relay) and takes this device off the list; **Change server** does that too. The app ends the
  connection when it leaves the screen and starts it again when it comes back, and what was playing carries on. The device's key is in
  the Keychain. A device that was never at home pastes an invite link where the address goes, or, for a TV, chooses **Join from away**:
  it shows a code to type into the server's Remote Access page (needs a server with `p2p-join`). The connecting is done by Wittyconnect,
  a Go library built from the server's source (AGPL-3.0-or-later) and linked into the app: `apple/scripts/build-wittyconnect.sh` builds
  it, for Apple TV as well, with a gomobile that has the tvOS targets. Without it the apps build and work as before. Not on Apple Vision
  Pro. Run for real in the Apple TV and iPhone simulators against a real server (`apple/scripts/p2p-check.sh`): paired at home, the home
  address taken away, a film played through the connection, the app off the screen and back; and, on Apple TV, joined by a code through
  the public address book. It adds about 24 MB to the installed app. **Never on a real Apple TV or iPhone**, and never across two
  routers: `docs/PLATFORMS.md` lists what to try on one.
- **A Flatpak and a Snap of the desktop app.** Each release has `wittymediaclient-<version>-linux-amd64.flatpak` and `.snap`, made by `electron-builder`
  from the same configuration as the other Linux packages (`npm run package:flatpak`, `npm run package:snap`). The Flatpak runs on the freedesktop
  runtime with Flathub's Electron base, and can reach the network, sound, the screen, controllers and Downloads; the Snap is a strictly confined
  core24 one. They're files on the release, not store listings, and neither has been installed or run yet: [INSTALLING.md](docs/INSTALLING.md#linux).
- **iPhone, iPad and Apple TV apps on every release, for AltStore and SideStore.** `wittymediaclient-<version>-ios.ipa` is one unsigned file for iPhone
  and iPad, and `-tvos.ipa` is Apple TV's, with its Top Shelf extension. A sideloading tool signs them with your own Apple ID. `apps.json` on the
  release is the AltStore source for the iOS app, written by `scripts/altstore-source.mjs` from the built app: its bundle identifier, version, lowest
  iOS, size and what it asks permission for. `apple/scripts/package-ipas.sh` makes the IPAs and checks each is a `Payload/<App>.app` zip for the right
  devices, with nothing of a signer's left in it. Never installed on a device.
- **Plasma Bigscreen: the launcher entry is checked on every build.** Bigscreen lists the Linux package as it is, and
  `scripts/test/bigscreen-entry.sh` fails the build if the `.deb`'s entry stops being one its home screen shows. The Flatpak is another way to
  install it there. `docs/PLASMA-BIGSCREEN.md` says what CI does for it.
- **CI builds every platform.** The `build` workflow now also makes the Flatpak, the Snap and the FreeBSD package, and the `release` workflow
  publishes them, the IPAs and the AltStore source along with the installers and APKs it already did.

## 0.4.1

- Android phones and tablets look like the website, and the first screen after signing in is drawn in the current design on every app.

## 0.4.0 (2026-11-05)

- **Desktop: what plays keeps playing behind other windows.** WittyTV, films and music no longer slow or stop when the
  window is minimised, hidden or covered: while something plays, the server's page isn't throttled and the system isn't
  allowed to suspend the app (the screen may still turn off), and for half a minute after, so the next episode starts.
  With the website's "Keep playing when this tab is in the background" turned off, the app does neither, and the page
  pauses as a browser tab would.
- **WittyPlay's Shelves on every Apple device.** A games library opens on Shelves, as the website's: Where you left off, the other games in
  progress, then a shelf for each console and the shelves the server picks, with every game A to Z at the foot. Games stand in their console's
  kind of case, as their cartridge, card or disc, or as spines in their covers' colours with letter dividers, as each device remembers; a game
  in progress has a ribbon. Press a game to pull it out, again to play it. On Apple TV the focused game rises into a preview at the top, and
  Play/Pause plays it. A console's page is its collection, and a game's page has its picture drifting behind, Resume, Where you left off, its
  moments and how it plays, or why it can't play here. iPhone, iPad and Apple Vision Pro open these instead of the website's game pages.
- **Games over WebRTC on every Apple device, and Apple TV now needs tvOS 17.** Where the server has its second stream, the Apple
  player connects over WebRTC first (LiveKit's build of libwebrtc), with the stream's WebSocket behind it, and plays Opus sound;
  every rumble motor, motion, lights and up to eight players pass through. tvOS 17 runs on every Apple TV HD and 4K.
- **iPhone, iPad and Apple Vision Pro play the server's games in the same player as Apple TV.** With no controller connected, the account's touch
  controls from the server are drawn over the game as the website draws them, in the layout saved for this device, upright or sideways; on a DS or
  3DS a finger on the picture is the stylus. Controllers work as on Apple TV.
- **Android: games stream over WebRTC first where the server has version 2 of its game stream.** Late frames are dropped rather than
  waited for, so a game keeps up on a poor network. The WebSocket takes over if WebRTC hasn't connected in 5 seconds or shown a
  picture in 8.
- **Android: an APK for each kind of processor, and a universal one.** WebRTC's library is 7 to 16 MB for each, so a device need only
  download its own: the README's Android section says which to install. The universal APK works anywhere, at 51 MB to 64-bit ARM's 16.
- **Android: the server's games play in the app, on phones, tablets and Android TV.** The server runs every game and streams it; the app shows the picture
  (H.264 through the device's own decoder, drawn as soon as it's decoded, or a picture a frame where the server has no encoder), plays the sound and sends the
  controls. Controllers play by the console's layout with the account's own profile over it, up to four at once, plugged in or out while playing, with rumble.
  A keyboard plays too. Phones and tablets show the account's touch controls from the server, and the DS's touch screen works with a finger. On a TV the remote
  is for the menus. Around the player: the games library in couch mode, a game's page with Play or Resume, save states and other versions, and the game menu
  (save, load, quick save and load, controllers, Press Start and Select, reset, save and quit). A game the server can't play says why, in the server's words.
  Going to the background pauses the game and comes back to it; saves are the server's, so a game carries on from the same place on any device.
- **Apple TV plays the server's games.** A games library opens as the website's couch mode: covers at the top with one at the front, tinted by its
  colour, then Continue playing, the consoles, the shelves and every game. A game's page has Play or Resume, Start over, a favourite, where you left off,
  its save states and how it plays. The game plays on the server, as it does for the website, and streams to the Apple TV, which decodes it in hardware and
  draws it with the person's picture settings, scanlines and bezels included. MFi, Xbox and PlayStation controllers and the Siri Remote work, with the
  account's controller profiles and shortcuts, up to four players (an NES's third and fourth through its Four Score, plugged in as they join), and a game menu to save, load, press Start or Select, change disc, reset and quit. Saves are the server's, so a
  game started on the TV resumes in a browser and the other way round. Games on someone's own PC still go through Moonlight. No emulator is in the app:
  `docs/WITTYPLAY-STREAMING.md` has the design.
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
- **Desktop: the connect screen follows the newer design.** It's WittyMediaClient until a server is added. A server
  found on the network shows only its address, "Found on your network" and a plain server icon, and says nothing about
  itself until it's added; one that's also saved is listed once, under Used before, with its own name. Once a server has
  proved who it is, its own logo shows on its screens and in the list, kept with it so it's there before it answers. On a
  TV the lockup is larger, every button is a pill, a focused field shows only the focus ring, and a focused number key
  fills instead of taking a ring.
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
