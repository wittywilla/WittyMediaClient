#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
# Writes the server's own SDUI catalogue into WittyKit as a bundled resource: SDUICatalog.builtIn is decoded
# from it, and the apps draw with it until the server's own catalogue has answered. Run it whenever the server's
# catalogue changes; SDUICatalogSyncTests fails while the bundled copy differs from a server checkout beside this one.
#
#   bash apple/scripts/sync-sdui-catalog.sh [path to WittyMediaServer]
#
# The server is the first argument, else WITTYMEDIASERVER_SRC, else a checkout beside this repository. It needs Go:
# the server prints its catalogue with `go run ./scripts/sdui-catalog`.
set -eu
cd "$(dirname "$0")/.."
SERVER="${1:-${WITTYMEDIASERVER_SRC:-}}"
if [ -z "$SERVER" ]; then
  for guess in ../../WittyMediaServer ../../../WittyMediaServer ../../../../WittyMediaServer; do
    if [ -f "$guess/scripts/sdui-catalog/main.go" ]; then SERVER="$guess"; break; fi
  done
fi
[ -n "$SERVER" ] && [ -f "$SERVER/scripts/sdui-catalog/main.go" ] || { echo "No server found: give the path to a WittyMediaServer checkout (or set WITTYMEDIASERVER_SRC)." >&2; exit 1; }
TO="WittyKit/Sources/WittyKit/Resources/sdui-catalog.json"
mkdir -p "$(dirname "$TO")"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
(cd "$SERVER" && go run ./scripts/sdui-catalog) > "$tmp"
mv "$tmp" "$TO"
trap - EXIT
rev="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["revision"])' "$TO")"
echo "Wrote $TO: catalogue revision $rev, from server commit $(cd "$SERVER" && git rev-parse --short HEAD 2>/dev/null || echo unknown)."
