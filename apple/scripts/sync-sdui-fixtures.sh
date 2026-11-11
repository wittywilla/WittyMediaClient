#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
# Copies the server's SDUI conformance fixtures to where WittyKit's tests look for them, for a machine or a CI
# job that has the server's repository somewhere other than beside this one. With the two repositories side by
# side (or WMS_SDUI_FIXTURES naming the folder) the tests read them where they are and this isn't needed.
#
#   bash apple/scripts/sync-sdui-fixtures.sh [path to WittyMediaServer]
#
# The copy is not committed (see .gitignore): the fixtures are the server's, and are 3 MB.
set -eu
cd "$(dirname "$0")/.."
SERVER="${1:-}"
if [ -z "$SERVER" ]; then
  for guess in ../../WittyMediaServer ../../../WittyMediaServer ../../../../WittyMediaServer; do
    if [ -d "$guess/pkg/sdui/conformance/fixtures" ]; then SERVER="$guess"; break; fi
  done
fi
FROM="$SERVER/pkg/sdui/conformance/fixtures"
[ -n "$SERVER" ] && [ -f "$FROM/index.json" ] || { echo "No fixtures found: give the path to a WittyMediaServer checkout." >&2; exit 1; }
TO="WittyKit/Tests/WittyKitTests/Fixtures/sdui"
rm -rf "$TO"
mkdir -p "$TO"
cp "$FROM"/*.json "$TO/"
# Which server commit they came from: a renderer pins the contract it was checked against.
(cd "$SERVER" && git rev-parse HEAD 2>/dev/null) > "$TO/SOURCE" || echo unknown > "$TO/SOURCE"
echo "Copied $(ls "$TO"/*.json | wc -l | tr -d ' ') files from $FROM (server commit $(cat "$TO/SOURCE"))."
