# Changelog

What changed in WittyMediaClient, newest first. What changed before it had a repository of its own is in the
[WittyMediaServer changelog](https://github.com/wittywilla/WittyMediaServer/blob/master/CHANGELOG.md).

## Unreleased

- WittyMediaClient is now a project of its own, developed and released from this repository.

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
