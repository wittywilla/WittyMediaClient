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
