#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
# Builds Wittyconnect, the library that reaches a server from away (peer to peer), into app/libs, where the build
# picks it up (app/build.gradle.kts). It isn't this repository's code: it is part of WittyMediaServer
# (pkg/wittyconnect/mobile, AGPL-3.0-or-later), built by that project's own script with the Go project's gomobile.
#
#   bash android/scripts/build-wittyconnect.sh                 needs Go, the Android SDK and its NDK
#   bash android/scripts/build-wittyconnect.sh --if-available  doesn't fail when Go, the NDK or the server's source is missing
#
# The server's source is WITTYMEDIASERVER_SRC, else a WittyMediaServer checkout beside this repository.
# Without the library the app still builds, and simply can't connect from away.
set -euo pipefail
given_source="${WITTYMEDIASERVER_SRC:-}"
[ -z "$given_source" ] || given_source="$(cd "$given_source" 2>/dev/null && pwd || echo "$given_source")"
cd "$(dirname "$0")/.."

lenient=0
[ "${1:-}" = "--if-available" ] && lenient=1
give() {
  if [ "$lenient" = 1 ]; then
    printf '\nNOT BUILT: %s\nThe app will build without it, and won'"'"'t be able to reach a server from away.\n\n' "$1" >&2
    exit 0
  fi
  echo "$1" >&2
  exit 1
}

source=""
for place in "$given_source" "../../WittyMediaServer" "../../../WittyMediaServer"; do
  if [ -n "$place" ] && [ -f "$place/scripts/build-wittyconnect-mobile.sh" ] && [ -f "$place/pkg/wittyconnect/mobile/mobile.go" ]; then
    source="$(cd "$place" && pwd)"
    break
  fi
done
[ -n "$source" ] || give "WittyMediaServer's source wasn't found. Set WITTYMEDIASERVER_SRC to a checkout that has pkg/wittyconnect/mobile."
# Joining's Wait is named Await in the Android library (Java's Object has a final wait()).
grep -q 'func (j \*Joining) Await' "$source"/pkg/wittyconnect/mobile/*.go 2>/dev/null ||
  give "The WittyMediaServer checkout at $source is too old for this app: its pkg/wittyconnect/mobile has no Android build of Joining."
command -v go >/dev/null 2>&1 || give "Go isn't installed, and the library is written in Go."
: "${ANDROID_HOME:=${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
export ANDROID_HOME
ls -d "$ANDROID_HOME"/ndk/* >/dev/null 2>&1 || [ -n "${ANDROID_NDK_HOME:-}" ] || give "No Android NDK. Install one: sdkmanager 'ndk;27.2.12479018'."

out="$PWD/app/libs"
mkdir -p "$out"
echo "Wittyconnect for Android, from $source"
OUT="$out" bash "$source/scripts/build-wittyconnect-mobile.sh" android
rm -f "$out/wittyconnect-sources.jar"
# Its licences go into the app beside the others (the licences screen lists them).
mkdir -p "$out/wittyconnect-notices"
mv -f "$out/THIRD-PARTY-NOTICES.txt" "$out/wittyconnect-notices/THIRD-PARTY-NOTICES.wittyconnect.txt"
(cd "$source" && git rev-parse HEAD 2>/dev/null || echo unknown) > "$out/wittyconnect.source-revision.txt"
echo "Done: $out/wittyconnect.aar"
