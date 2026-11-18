#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
#
# Fails unless every desktop app electron-builder left in the given folder carries wittyconnect,
# the helper that reaches a server from away, and its notices. Without it the app says "its
# connection helper is missing" the first time someone connects from away.
#
#   scripts/test/helper-packaged.sh desktop/out
set -euo pipefail
out=${1:?the folder electron-builder wrote}
checked=0
missing=0
need() {
  checked=$((checked + 1))
  if [ -s "$1" ]; then echo "ok: $1"; else echo "MISSING: $1"; missing=$((missing + 1)); fi
}
for d in "$out"/win-unpacked "$out"/win-*-unpacked; do
  [ -d "$d" ] || continue
  need "$d/resources/wittyconnect.exe"
  need "$d/resources/THIRD-PARTY-NOTICES.wittyconnect.txt"
done
for d in "$out"/linux-unpacked "$out"/linux-*-unpacked; do
  [ -d "$d" ] || continue
  need "$d/resources/wittyconnect"
  need "$d/resources/THIRD-PARTY-NOTICES.wittyconnect.txt"
done
for app in "$out"/mac*/*.app; do
  [ -d "$app" ] || continue
  need "$app/Contents/Resources/wittyconnect"
  need "$app/Contents/Resources/THIRD-PARTY-NOTICES.wittyconnect.txt"
done
if [ "$checked" -eq 0 ]; then
  echo "No unpacked app found in $out" >&2
  exit 1
fi
[ "$missing" -eq 0 ] || { echo "$missing of $checked files missing: build the helper first (desktop/scripts/build-wittyconnect.mjs)" >&2; exit 1; }
