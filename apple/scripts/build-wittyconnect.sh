#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
# Builds Wittyconnect, the library that reaches a server from away (peer to peer), into
# apple/Frameworks, where the Xcode project looks for it. For a Mac with Xcode and Go.
#
# The library isn't this repository's code. It is part of WittyMediaServer (pkg/wittyconnect, under
# the AGPL-3.0-or-later) and is built from a checkout of that: the folder in WITTYMEDIASERVER_SRC, or
# a WittyMediaServer folder beside this repository. That checkout's own script does the building
# (scripts/build-wittyconnect-mobile.sh apple), with a gomobile that has an Apple TV target, pinned
# there and kept in that checkout's .tools folder. Its third-party notices are written beside the
# library, and go into the app with it.
#
#   bash apple/scripts/build-wittyconnect.sh                 Apple TV, iPhone and iPad, and their simulators
#   bash apple/scripts/build-wittyconnect.sh --if-available  don't fail when Go or the server's source is missing
#
# Without the library the apps still build, and simply can't connect from away.
set -euo pipefail
# Wherever it was given from, before this moves to apple/.
given_source="${WITTYMEDIASERVER_SRC:-}"
[ -z "$given_source" ] || given_source="$(cd "$given_source" 2>/dev/null && pwd || echo "$given_source")"
cd "$(dirname "$0")/.."

lenient=0
[ "${1:-}" = "--if-available" ] && lenient=1
give() {
  if [ "$lenient" = 1 ]; then
    printf '\nNOT BUILT: %s\nThe apps will build without it, and won'"'"'t be able to reach a server from away.\n\n' "$1" >&2
    exit 0
  fi
  echo "$1" >&2
  exit 1
}

source=""
for place in "$given_source" "../../WittyMediaServer"; do
  if [ -n "$place" ] && [ -f "$place/scripts/build-wittyconnect-mobile.sh" ] && [ -f "$place/pkg/wittyconnect/mobile/mobile.go" ]; then
    source="$(cd "$place" && pwd)"
    break
  fi
done
[ -n "$source" ] || give "WittyMediaServer's source wasn't found. Set WITTYMEDIASERVER_SRC to a checkout that has pkg/wittyconnect/mobile."
# A checkout from before the library had what these apps call, or before it was built for Apple TV.
if ! grep -q 'func StartJoin' "$source/pkg/wittyconnect/mobile/mobile.go" || ! grep -q 'tvos' "$source/scripts/build-wittyconnect-mobile.sh"; then
  give "The WittyMediaServer checkout at $source is too old for these apps: it needs 0.8.0-alpha's pkg/wittyconnect, with Apple TV in its build script."
fi
command -v go >/dev/null 2>&1 || give "Go isn't installed, and the library is written in Go."
command -v xcodebuild >/dev/null 2>&1 || give "Xcode isn't installed."

out="$PWD/Frameworks"
mkdir -p "$out"
echo "Wittyconnect for Apple TV, iPhone and iPad, from $source"
OUT="$out" bash "$source/scripts/build-wittyconnect-mobile.sh" apple
# Named for what it is about, as the desktop app's copy is.
mv -f "$out/THIRD-PARTY-NOTICES.txt" "$out/THIRD-PARTY-NOTICES.wittyconnect.txt"
# Which source it was built from, for whoever asks what is in a build.
(cd "$source" && git rev-parse HEAD 2>/dev/null || echo unknown) > "$out/Wittyconnect.source-revision.txt"
echo "Done: $out/Wittyconnect.xcframework"
