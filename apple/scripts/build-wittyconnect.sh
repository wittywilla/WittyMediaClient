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
#   bash apple/scripts/build-wittyconnect.sh --if-missing    only when apple/Frameworks hasn't got it: from this Mac's
#                                                            cache when built before from the same source, else built
#                                                            once into the cache (what the apps' build phase runs)
#
# Without the library the apps still build, and simply can't connect from away.
set -euo pipefail
# Wherever it was given from, before this moves to apple/.
given_source="${WITTYMEDIASERVER_SRC:-}"
[ -z "$given_source" ] || given_source="$(cd "$given_source" 2>/dev/null && pwd || echo "$given_source")"
cd "$(dirname "$0")/.."

lenient=0
only_missing=0
for arg in "$@"; do
  case "$arg" in
    (--if-available) lenient=1 ;;
    (--if-missing) only_missing=1 ;;
  esac
done
# Run by Xcode's build phase: its PATH hasn't got Homebrew's or Go's folders, and what it should say goes as a warning.
in_xcode=0
[ -n "${XCODE_VERSION_ACTUAL:-}" ] && in_xcode=1
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$HOME/go/bin"
give() {
  if [ "$lenient" = 1 ]; then
    if [ "$in_xcode" = 1 ]; then
      echo "warning: Wittyconnect isn't built, so this build can't connect to a server from away (peer to peer): $1 Run apple/scripts/build-wittyconnect.sh with WITTYMEDIASERVER_SRC set to a WittyMediaServer checkout."
    else
      printf '\nNOT BUILT: %s\nThe apps will build without it, and won'"'"'t be able to reach a server from away.\n\n' "$1" >&2
    fi
    exit 0
  fi
  echo "$1" >&2
  exit 1
}

out="$PWD/Frameworks"
# Already here: nothing to do.
if [ "$only_missing" = 1 ] && [ -d "$out/Wittyconnect.xcframework" ]; then
  exit 0
fi

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
bash ../shared/scripts/go-mod-download.sh "$source" || give "The server's Go modules couldn't be downloaded."
command -v xcodebuild >/dev/null 2>&1 || give "Xcode isn't installed."

mkdir -p "$out"
revision="$(cd "$source" && git rev-parse HEAD 2>/dev/null || echo unknown)"
# One build for every checkout and worktree on this Mac: the library is the same for the same server source.
cache="${WITTYCONNECT_CACHE:-$HOME/Library/Caches/WittyMediaClient/wittyconnect}/$revision"
# Xcode doesn't compile a file again because `canImport(Wittyconnect)` would now answer otherwise: the file that
# asks is touched, so a build after the library arrives has it.
arrived() { touch "$PWD/App/PeerLibrary.swift" 2>/dev/null || true; }
copy_from() {
  rm -rf "$out/Wittyconnect.xcframework"
  cp -R "$1/Wittyconnect.xcframework" "$out/"
  cp -f "$1/THIRD-PARTY-NOTICES.wittyconnect.txt" "$out/" 2>/dev/null || true
  echo "$revision" > "$out/Wittyconnect.source-revision.txt"
  arrived
}
if [ "$only_missing" = 1 ] && [ "$revision" != unknown ] && [ -d "$cache/Wittyconnect.xcframework" ]; then
  copy_from "$cache"
  echo "Wittyconnect from this Mac's cache (server $revision)"
  exit 0
fi
build_to="$out"
[ "$only_missing" = 1 ] && [ "$revision" != unknown ] && build_to="$cache.partial" && rm -rf "$build_to" && mkdir -p "$build_to"
echo "Wittyconnect for Apple TV, iPhone and iPad, from $source"
OUT="$build_to" bash "$source/scripts/build-wittyconnect-mobile.sh" apple
# Named for what it is about, as the desktop app's copy is.
mv -f "$build_to/THIRD-PARTY-NOTICES.txt" "$build_to/THIRD-PARTY-NOTICES.wittyconnect.txt"
if [ "$build_to" != "$out" ]; then
  rm -rf "$cache" && mv "$build_to" "$cache"
  copy_from "$cache"
else
  # Which source it was built from, for whoever asks what is in a build; and kept for the other checkouts here.
  echo "$revision" > "$out/Wittyconnect.source-revision.txt"
  if [ "$revision" != unknown ]; then
    rm -rf "$cache" && mkdir -p "$cache"
    cp -R "$out/Wittyconnect.xcframework" "$out/THIRD-PARTY-NOTICES.wittyconnect.txt" "$cache/"
  fi
fi
arrived
echo "Done: $out/Wittyconnect.xcframework"
