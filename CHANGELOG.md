# Changelog

What changed in WittyMediaClient, newest first. What changed before it had a repository of its own is in the
[WittyMediaServer changelog](https://github.com/wittywilla/WittyMediaServer/blob/master/CHANGELOG.md).

## Unreleased

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
