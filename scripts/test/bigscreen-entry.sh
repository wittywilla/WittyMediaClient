#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
# Checks that a Linux package's launcher entry is one Plasma Bigscreen's home screen will list, and that
# the app it starts can open as a TV app. Bigscreen needs no key or category of its own: its
# applicationlistmodel.cpp lists every application that isn't hidden, isn't run in a terminal and has
# something to run (docs/PORTING.md, Plasma Bigscreen). The TV interface comes from the app, which reads
# the session's PLASMA_PLATFORM and takes --tv and --no-tv (desktop/tv.js), so the entry carries no flag:
# the same entry has to open the desktop layout on a desk.
#
#   scripts/test/bigscreen-entry.sh desktop/out/wittymediaclient-<version>-linux-amd64.deb
#   scripts/test/bigscreen-entry.sh some.desktop
#
# A .deb needs dpkg-deb. Anything else is read as the entry itself.
set -euo pipefail

from=${1:?Give a .deb or a .desktop file}
fail() { echo "FAIL: $*" >&2; exit 1; }

case "$from" in
  *.deb)
    entry=$(dpkg-deb --fsys-tarfile "$from" | tar -xO --wildcards '*usr/share/applications/*.desktop') || fail "$from has no launcher entry in usr/share/applications"
    dpkg-deb --fsys-tarfile "$from" | tar -t | grep -Eq '(^|/)usr/share/icons/hicolor/[^/]+/apps/wittymediaclient\.png$' || fail "$from has no wittymediaclient icon for the launcher"
    ;;
  *) entry=$(cat "$from") ;;
esac

# Only the [Desktop Entry] group: an action's keys further down aren't the launcher's.
main=$(printf '%s\n' "$entry" | awk '/^\[/{inside = ($0 == "[Desktop Entry]")} inside')
key() { printf '%s\n' "$main" | sed -n "s/^$1=//p" | head -1; }

[ "$(key Type)" = Application ] || fail "Type is '$(key Type)', not Application"
[ -n "$(key Name)" ] || fail "no Name"
[ -n "$(key Exec)" ] || fail "no Exec: the launcher has nothing to run"
[ -n "$(key Icon)" ] || fail "no Icon"
[ "$(key Terminal)" != true ] || fail "Terminal=true: Bigscreen leaves out what runs in a terminal"
[ "$(key NoDisplay)" != true ] || fail "NoDisplay=true: Bigscreen leaves out hidden entries"
[ "$(key Hidden)" != true ] || fail "Hidden=true: Bigscreen leaves out hidden entries"
case "$(key Exec)" in
  *--tv*|*--no-tv*) fail "Exec is '$(key Exec)': the entry mustn't force TV mode on or off, the session decides" ;;
esac
categories=";$(key Categories)"
for wanted in AudioVideo Video TV; do
  case "$categories" in *";$wanted;"*) ;; *) fail "Categories is '$(key Categories)', without $wanted" ;; esac
done
# Game would move it to Bigscreen's row for games, away from the other media apps.
case "$categories" in *";Game;"*) fail "Categories has Game, which puts it in Bigscreen's games row" ;; esac

echo "ok: '$(key Name)' is an entry Plasma Bigscreen lists: Exec=$(key Exec), Categories=$(key Categories)"
