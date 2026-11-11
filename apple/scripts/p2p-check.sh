#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
# Runs the Apple TV app (or the iPhone one) in a simulator against a real WittyMediaServer with peer-to-peer
# connections on, with the real Wittyconnect library, and checks what docs/PLATFORMS.md says of it:
#
#   at home   the TV shows a code, which is approved as from a phone; the app puts this device on
#             the server's list by itself
#   away      the server's home address is taken away: the app finds the server peer to peer, is
#             still signed in, and plays a film through the connection, which the server counts
#             as from the internet; the app leaves the screen and comes back, and the film goes on
#
# For a Mac with Xcode, XcodeGen, Go and ffmpeg, and a checkout of WittyMediaServer (the folder in
# WITTYMEDIASERVER_SRC, or a WittyMediaServer folder beside this repository). Nothing is signed with
# anyone's account and nothing leaves this machine: the server it builds runs here on ports of its own, with its own
# data folder and a film it makes, and only the layers that need nobody else are turned on.
#
#   bash apple/scripts/p2p-check.sh          the Apple TV app
#   bash apple/scripts/p2p-check.sh ios      the iPhone app, the same way
#
# P2P_CHECK_PUBLIC=1 turns on finding the server through the public network as well (the address
# book, relays, hole punching), as an owner would have it: slower, and it contacts those computers.
# It adds a third part, which nothing else can check: a device that has never met the server shows
# a code, the code is typed into the server, and the two find each other through the address book.
# The router is never asked for anything either way. P2P_CHECK_DEVICE names another simulator.
# Everything it writes goes in apple/build/p2p-check, and the app's own log is copied there.
set -euo pipefail
cd "$(dirname "$0")/.."
APPLE="$PWD"
WORK="$APPLE/build/p2p-check"
BUNDLE=com.wittywilla.wittymediaclient
case "${1:-tvos}" in
  (tvos) scheme=WittyMedia-tvOS-Checks; system="tvOS Simulator"; kind="Apple TV" ;;
  (ios) scheme=WittyMedia-iOS-Checks; system="iOS Simulator"; kind="iPhone" ;;
  (*) echo "usage: $0 [tvos|ios]" >&2; exit 2 ;;
esac
PASSWORD="check-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 16 || true)"

for tool in xcodebuild xcodegen go ffmpeg python3 curl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool isn't installed, and this check needs it." >&2; exit 2; }
done
source=""
for place in "${WITTYMEDIASERVER_SRC:-}" "../../WittyMediaServer"; do
  if [ -n "$place" ] && [ -f "$place/cmd/wittymediaserver/main.go" ]; then source="$(cd "$place" && pwd)"; break; fi
done
[ -n "$source" ] || { echo "WittyMediaServer's source wasn't found. Set WITTYMEDIASERVER_SRC to a checkout of it." >&2; exit 2; }

rm -rf "$WORK"
mkdir -p "$WORK/data" "$WORK/media/Films/Check Film (2020)"
say() { printf '%s\n' "$*" | tee -a "$WORK/report.txt"; }

server_pid=""
forward_pid=""
device=""
finish() {
  [ -n "$forward_pid" ] && kill "$forward_pid" 2>/dev/null || true
  [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null || true
  if [ -n "$device" ]; then
    # What the app wrote about itself, before it goes.
    container="$(xcrun simctl get_app_container "$device" "$BUNDLE" data 2>/dev/null || true)"
    [ -n "$container" ] && cp "$container/Library/Caches/logs/client.log" "$WORK/client.log" 2>/dev/null || true
    xcrun simctl terminate "$device" "$BUNDLE" 2>/dev/null || true
  fi
}
trap finish EXIT

free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
json() { python3 -c 'import sys,json; d=json.load(sys.stdin); print(eval(sys.argv[1], {"d": d}))' "$1"; }

if [ ! -d "$APPLE/Frameworks/Wittyconnect.xcframework" ]; then
  WITTYMEDIASERVER_SRC="$source" bash "$APPLE/scripts/build-wittyconnect.sh"
fi

say "The server, from $source"
(cd "$source" && GOWORK=off go build -o "$WORK/wittymediaserver" ./cmd/wittymediaserver)
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=640x360:rate=24" -f lavfi -i "sine=frequency=440:sample_rate=48000" -t 600 \
  -c:v libx264 -preset veryfast -crf 30 -pix_fmt yuv420p -g 48 -c:a aac -b:a 96k -movflags +faststart \
  "$WORK/media/Films/Check Film (2020)/Check Film (2020).mp4"

port="$(free_port)"
direct="http://127.0.0.1:$port"
WMS_NO_DIALOG=1 WMS_NO_BROWSER=1 "$WORK/wittymediaserver" -data "$WORK/data" -listen "127.0.0.1:$port" -open-browser=false >"$WORK/server.log" 2>&1 &
server_pid=$!
disown "$server_pid"
for _ in $(seq 1 60); do curl -fsS -m 2 "$direct/api/health" >/dev/null 2>&1 && break; sleep 0.5; done
curl -fsS -m 2 "$direct/api/health" >/dev/null || { tail -20 "$WORK/server.log"; echo "The server didn't start." >&2; exit 1; }

post() { curl -fsS -m 30 -X "$1" "$direct$2" -H 'Content-Type: application/json' ${token:+-H "Authorization: Bearer $token"} -d "$3"; }
token=""
token="$(post POST /api/setup "{\"name\":\"owner\",\"password\":\"$PASSWORD\",\"device\":\"check\",\"acknowledgedLegal\":true}" | json 'd["token"]')"
# Nothing is written beside the film. And the server doesn't announce itself on the network: away
# from home nothing would hear it, and here the simulator would, and find the server's own address.
post PUT /api/settings '{"saveMetadata":"0","lanDiscovery":"0"}' >/dev/null
post POST /api/libraries "{\"name\":\"Films\",\"type\":\"movies\",\"paths\":[\"$WORK/media/Films\"]}" >/dev/null
post POST /api/libraries/1/scan '{}' >/dev/null
item=""
for _ in $(seq 1 60); do
  item="$(curl -fsS -m 10 "$direct/api/v1/items?library=1" -H "Authorization: Bearer $token" | json '(d.get("items") or [{}])[0].get("id", "")')"
  [ -n "$item" ] && break
  sleep 0.5
done
[ -n "$item" ] || { echo "The server didn't find the film." >&2; exit 1; }

public=false
[ "${P2P_CHECK_PUBLIC:-}" = 1 ] && public=true
post PUT /api/v1/p2p/settings "{\"enabled\":true,\"accept\":true,\"port\":0,\"layers\":{\"dht\":$public,\"relay\":$public,\"holePunch\":$public,\"portMap\":false,\"ipv6\":false},\"devicesOnly\":true,\"relayKbps\":4000,\"relayForOthers\":false,\"staticRelays\":[]}" >/dev/null
server_id="$(curl -fsS -m 10 "$direct/api/v1/p2p" -H "Authorization: Bearer $token" | json 'd.get("serverId", "")')"
[ -n "$server_id" ] || { echo "The server didn't turn peer-to-peer connections on." >&2; exit 1; }
say "ok    the server is up with peer-to-peer connections on ($([ "$public" = true ] && echo "found through the public network too" || echo "this machine only"))"

# The server's home address, as the app knows it: a forwarder, so it can be taken away while the
# server stays. On this machine's own network address when it has one, as a server at home is.
lan="$(ipconfig getifaddr "$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')" 2>/dev/null || true)"
[ -n "$lan" ] || lan=127.0.0.1
home_port="$(free_port)"
home="http://$lan:$home_port"
python3 - "$lan" "$home_port" "$port" >"$WORK/forwarder.log" 2>&1 <<'PY' &
import socket, sys, threading
host, port, to = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
def pump(a, b):
    try:
        while True:
            data = a.recv(65536)
            if not data:
                break
            b.sendall(data)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            s.close()
listener = socket.socket()
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind((host, port))
listener.listen(64)
while True:
    client, _ = listener.accept()
    try:
        server = socket.create_connection(("127.0.0.1", to), timeout=5)
        server.settimeout(None)
    except OSError:
        client.close()
        continue
    threading.Thread(target=pump, args=(client, server), daemon=True).start()
    threading.Thread(target=pump, args=(server, client), daemon=True).start()
PY
forward_pid=$!
disown "$forward_pid"
for _ in $(seq 1 20); do curl -fsS -m 2 "$home/api/health" >/dev/null 2>&1 && break; sleep 0.25; done
curl -fsS -m 2 "$home/api/health" >/dev/null || { echo "The forwarder at $home didn't start." >&2; exit 1; }

device="$(xcrun simctl list devices available | grep -E "^ +${P2P_CHECK_DEVICE:-$kind}" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[ -n "$device" ] || { echo "No $kind simulator. Add one in Xcode's settings, under Platforms." >&2; exit 2; }
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null
# As new: no server chosen, nobody signed in.
xcrun simctl uninstall "$device" "$BUNDLE" 2>/dev/null || true

xcodegen generate >"$WORK/xcodegen.log" 2>&1
# Signed for this Mac only ("sign to run locally"), which needs no account: an app with no signature
# at all is refused the simulator's keychain, and the sign-in and the device's key are kept there.
run() { # what xcodebuild does, log name, then anything else for it
  local what="$1" log="$2"
  shift 2
  TEST_RUNNER_CHECK_HOME="$home" TEST_RUNNER_CHECK_DIRECT="$direct" TEST_RUNNER_CHECK_TOKEN="$token" TEST_RUNNER_CHECK_PASSWORD="$PASSWORD" TEST_RUNNER_CHECK_ITEM="$item" TEST_RUNNER_CHECK_PUBLIC="${P2P_CHECK_PUBLIC:-}" \
    xcodebuild "$what" -project WittyMedia.xcodeproj -scheme "$scheme" -destination "platform=$system,id=$device" \
    -derivedDataPath DerivedData/p2p-check -resultBundlePath "$WORK/$log.xcresult" -collect-test-diagnostics never \
    CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="" "$@" >"$WORK/$log.log" 2>&1 || return 1
  # A run that found nothing to run is not a pass.
  [ "$what" != test-without-building ] || grep -q "Executed 1 test, with 0 failures" "$WORK/$log.log"
}
run build-for-testing build || { grep -E ' error: |\*\* ' "$WORK/build.log" | sort -u | head -30; say "FAIL  building the app and the check: see build.log"; exit 1; }
say "ok    the app and the check are built for the $kind simulator"

if run test-without-building home -only-testing:"$scheme/AwayCheck/testHome"; then
  say "ok    at home: a code approved from another device signs the $kind in, and it adds itself to the server's list"
else
  grep -E 'error: |XCTAssert|failed' "$WORK/home.log" | sort -u | head -20
  say "FAIL  at home: see home.log"
  exit 1
fi

# Away: the home address stops answering. The server itself stays where it is.
kill "$forward_pid" 2>/dev/null || true
forward_pid=""
for _ in $(seq 1 20); do curl -fsS -m 1 "$home/api/health" >/dev/null 2>&1 || break; sleep 0.25; done
if run test-without-building away -only-testing:"$scheme/AwayCheck/testAway"; then
  grep -h '^AwayCheck: ' "$WORK/away.log" | sed 's/^AwayCheck: /      /' | tee -a "$WORK/report.txt" || true
  say "ok    away: the $kind finds the server peer to peer, still signed in, and plays the film through it, before and after leaving the screen"
else
  grep -E 'error: |XCTAssert|failed' "$WORK/away.log" | sort -u | head -20
  say "FAIL  away: see away.log"
  exit 1
fi
if [ "$public" = true ]; then
  # A device that has never met this server: the app as new again, and the server found by a code.
  xcrun simctl uninstall "$device" "$BUNDLE" 2>/dev/null || true
  if run test-without-building join -only-testing:"$scheme/AwayCheck/testJoinFromAway"; then
    grep -h '^AwayCheck: ' "$WORK/join.log" | sed 's/^AwayCheck: /      /' | tee -a "$WORK/report.txt" || true
    say "ok    joining: a $kind that never met the server shows a code, and typing it into the server brings the two together and signs it in"
  else
    grep -E 'error: |XCTAssert|failed' "$WORK/join.log" | sort -u | head -20
    say "FAIL  joining by a code: see join.log"
    exit 1
  fi
fi
say "All of it passed, in the $(xcrun simctl list devices | grep "$device" | sed -E 's/^ +//; s/ \(.*//') simulator. A real device is another matter: docs/PLATFORMS.md says what to try on one."
