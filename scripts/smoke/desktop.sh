#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
# The desktop app's smoke test: the real app (Electron, under xvfb on Linux) against a real server
# that the server repository's scripts/smoke/server.sh set up. Each way of adding a server the
# harnesses in desktop/test/app know, then a film, then TV mode:
#
#   address + code  real-server.js: Type an address, a security code from the server, a film plays
#   pairing         the same with WMC_PAIR=1: a code and PIN on screen, approved as from a phone
#   TV mode         real-server.js --tv: the same with a remote's keys alone, in TV mode
#   from away       p2p-real.js: at home, then the address stops answering and the app finds the
#                   server peer to peer, still signed in; then the device is removed and shut out
#   invite link     p2p-real.js --phase=invite: a link pasted on the connect screen
#   every way       desktop/test/app/add-server-real.js, where this checkout has it: found, code,
#                   address and password
#
#   SERVER_SRC=<server checkout> SMOKE_OUT=<run folder> scripts/smoke/desktop.sh <wittyconnect>
#
# $SMOKE_OUT/server.env is server.sh's. Pictures go to $SMOKE_OUT/desktop-<run>/.
set -uo pipefail
connect=$(cd "$(dirname "${1:?the wittyconnect binary}")" && pwd)/$(basename "$1")
here=$(cd "$(dirname "$0")/../.." && pwd)
. "${SERVER_SRC:?the server checkout}/scripts/smoke/lib.sh"
set -a; . "$SMOKE_OUT/server.env"; set +a
desk=$here/desktop
export SMOKE_KEEP_GOING=${SMOKE_KEEP_GOING:-1}
electron() {
  local shots=$SMOKE_OUT/desktop-$1; shift
  mkdir -p "$shots"
  ( cd "$desk" && env WMC_SHOTS="$shots" WMC_USER="$WMS_NAME" WMC_PASSWORD="$WMS_PASS" WMC_TEST_DIR="$SMOKE_OUT/desktop-data" \
      WITTYCONNECT="$connect" ${XVFB:-xvfb-run -a -s "-screen 0 1280x860x24"} node_modules/.bin/electron "$@" )
}
mkdir -p "$SMOKE_OUT/desktop-data"

step "Desktop: Type an address, a security code, a film plays"
WMC_SERVER=$WMS_URL electron address-code test/app/real-server.js >>"$LOG" 2>&1 || fail "see the log"

step "Desktop: pairing with a code and PIN"
WMC_SERVER=$WMS_URL WMC_PAIR=1 electron pairing test/app/real-server.js >>"$LOG" 2>&1 || fail "see the log"

step "Desktop: TV mode with a remote's keys"
WMC_SERVER=$WMS_URL electron tv test/app/real-server.js --tv >>"$LOG" 2>&1 || fail "see the log"

# From away: the app is told a forwarder's address, which stops answering between the runs.
step "Desktop: at home, then from away peer to peer"
port=${WMS_URL##*:}
api PUT /api/p2p/settings "{\"accept\":true,\"enabled\":true,\"port\":$((port + 2)),\"devicesOnly\":true,\"layers\":{\"dht\":false,\"relay\":false,\"holePunch\":false,\"portMap\":false,\"ipv6\":false}}" >>"$LOG"
echo >>"$LOG"
fport=$((port + 5))
socat "TCP-LISTEN:$fport,bind=127.0.0.1,fork,reuseaddr" "TCP:127.0.0.1:$port" &
fwd=$!
sleep 1
WMC_SERVER=http://127.0.0.1:$fport WMC_DIRECT=$WMS_URL electron p2p-home test/app/p2p-real.js --phase=home >>"$LOG" 2>&1 || { kill $fwd; fail "at home: see the log"; }
kill $fwd; wait $fwd 2>/dev/null
WMC_SERVER=http://127.0.0.1:$fport WMC_DIRECT=$WMS_URL electron p2p-away test/app/p2p-real.js --phase=away >>"$LOG" 2>&1 || fail "from away: see the log"

step "Desktop: a removed device is shut out"
WMC_SERVER=http://127.0.0.1:$fport WMC_DIRECT=$WMS_URL electron p2p-revoked test/app/p2p-real.js --phase=revoked >>"$LOG" 2>&1 || fail "see the log"

step "Desktop: an invite link pasted on the connect screen"
WMC_SERVER=http://127.0.0.1:$fport WMC_DIRECT=$WMS_URL electron p2p-invite test/app/p2p-real.js --phase=invite >>"$LOG" 2>&1 || fail "see the log"

if [ -f "$desk/test/app/add-server-real.js" ]; then
  for way in found code address password; do
    step "Desktop: Add a server, $way"
    WMC_SERVER=$WMS_URL electron "way-$way" test/app/add-server-real.js "--way=$way" >>"$LOG" 2>&1 || fail "see the log"
  done
fi
finish
