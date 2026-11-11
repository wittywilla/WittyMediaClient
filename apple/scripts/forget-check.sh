#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
# Runs the iPhone app (or the Apple TV one) in a simulator against two real WittyMediaServers, and checks
# that removing a server a device remembers takes everything the app kept for it and nothing of the other:
#
#   both      a code approved on each server: both are remembered, and the device is signed in to the second
#   other     Manage servers removes the first (with Undo on an iPhone); the second stays signed in, and on
#             disk only the first server's settings are gone
#   in use    the server in use is removed: the app asks, signs out, the server ends the sign-in, and
#             nothing of either server is left on disk
#   list      the list of servers: a swipe and Undo, Edit, the card's menu, Manage servers and Remove all
#             (the card's menu, where the remote's focus goes, and Manage servers on Apple TV)
#   old list  a list as an older version kept it, with one server in it twice: it becomes one entry, and
#             what was kept under the address that went follows it; then "Remove servers not reached for…"
#   changed   a remembered address answering with another key: the warning, and "Remove the old server"
#
# For a Mac with Xcode, XcodeGen and Go, and a checkout of WittyMediaServer (the folder in
# WITTYMEDIASERVER_SRC, or a WittyMediaServer folder beside this repository). Nothing is signed with anyone's
# account and nothing leaves this machine: the two servers it builds run here on ports of their own, each
# with its own empty data folder, and neither announces itself on the network.
#
#   bash apple/scripts/forget-check.sh          the iPhone app
#   bash apple/scripts/forget-check.sh tvos     the Apple TV app, the same way
#
# FORGET_CHECK_DEVICE names another simulator. Everything it writes goes in apple/build/forget-check.
set -euo pipefail
cd "$(dirname "$0")/.."
APPLE="$PWD"
WORK="$APPLE/build/forget-check"
BUNDLE=com.wittywilla.wittymediaclient
case "${1:-ios}" in
  (ios) scheme=WittyMedia-iOS-Checks; system="iOS Simulator"; kind="iPhone" ;;
  (tvos) scheme=WittyMedia-tvOS-Checks; system="tvOS Simulator"; kind="Apple TV" ;;
  (*) echo "usage: $0 [ios|tvos]" >&2; exit 2 ;;
esac
PASSWORD="check-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 16 || true)"

for tool in xcodebuild xcodegen go python3 curl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool isn't installed, and this check needs it." >&2; exit 2; }
done
source=""
for place in "${WITTYMEDIASERVER_SRC:-}" "../../WittyMediaServer"; do
  if [ -n "$place" ] && [ -f "$place/cmd/wittymediaserver/main.go" ]; then source="$(cd "$place" && pwd)"; break; fi
done
[ -n "$source" ] || { echo "WittyMediaServer's source wasn't found. Set WITTYMEDIASERVER_SRC to a checkout of it." >&2; exit 2; }

rm -rf "$WORK"
mkdir -p "$WORK/a" "$WORK/b"
say() { printf '%s\n' "$*" | tee -a "$WORK/report.txt"; }

pids=""
device=""
finish() {
  for pid in $pids; do kill "$pid" 2>/dev/null || true; done
  if [ -n "$device" ]; then
    container="$(xcrun simctl get_app_container "$device" "$BUNDLE" data 2>/dev/null || true)"
    [ -n "$container" ] && cp "$container/Library/Caches/logs/client.log" "$WORK/client.log" 2>/dev/null || true
    xcrun simctl terminate "$device" "$BUNDLE" 2>/dev/null || true
  fi
}
trap finish EXIT

free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }

say "The server, from $source"
(cd "$source" && GOWORK=off go build -o "$WORK/wittymediaserver" ./cmd/wittymediaserver)
# On this machine's own network address when it has one, as a server at home is.
lan="$(ipconfig getifaddr "$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')" 2>/dev/null || true)"
[ -n "$lan" ] || lan=127.0.0.1
start_server() { # folder: prints the address the app is told, once the server is set up
  local port own token
  port="$(free_port)"
  # Set up from this machine itself, which is the only place a new server lets it be done from.
  own="http://127.0.0.1:$port"
  WMS_NO_DIALOG=1 WMS_NO_BROWSER=1 "$WORK/wittymediaserver" -data "$WORK/$1" -listen "0.0.0.0:$port" -open-browser=false >"$WORK/server-$1.log" 2>&1 &
  echo $! >"$WORK/$1.pid"
  for _ in $(seq 1 60); do curl -fsS -m 2 "$own/api/health" >/dev/null 2>&1 && break; sleep 0.5; done
  token="$(curl -fsS -m 30 -X POST "$own/api/setup" -H 'Content-Type: application/json' \
    -d "{\"name\":\"owner\",\"password\":\"$PASSWORD\",\"device\":\"check\",\"acknowledgedLegal\":true}" | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])')"
  # It doesn't announce itself: the list of servers then holds only what the check put there.
  curl -fsS -m 30 -X PUT "$own/api/settings" -H 'Content-Type: application/json' -H "Authorization: Bearer $token" -d '{"saveMetadata":"0","lanDiscovery":"0"}' >/dev/null
  echo "http://$lan:$port"
}
a="$(start_server a)" || { pids="$(cat "$WORK/a.pid" 2>/dev/null || true)"; tail -5 "$WORK/server-a.log"; echo "The first server didn't start." >&2; exit 1; }
pids="$(cat "$WORK/a.pid")"
b="$(start_server b)" || { tail -5 "$WORK/server-b.log"; echo "The second server didn't start." >&2; exit 1; }
pids="$pids $(cat "$WORK/b.pid")"
say "ok    two servers are up, at $a and $b"

device="$(xcrun simctl list devices available | grep -E "^ +${FORGET_CHECK_DEVICE:-$kind}" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[ -n "$device" ] || { echo "No $kind simulator. Add one in Xcode's settings, under Platforms." >&2; exit 2; }
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null
# As new: no server remembered, nobody signed in.
xcrun simctl uninstall "$device" "$BUNDLE" 2>/dev/null || true

xcodegen generate >"$WORK/xcodegen.log" 2>&1
# Signed for this Mac only ("sign to run locally"), which needs no account: an app with no signature
# at all is refused the simulator's keychain, and the sign-in is kept there.
run() { # what xcodebuild does, log name, then anything else for it
  local what="$1" log="$2"
  shift 2
  TEST_RUNNER_CHECK_A="$a" TEST_RUNNER_CHECK_B="$b" TEST_RUNNER_CHECK_USER=owner TEST_RUNNER_CHECK_PASSWORD="$PASSWORD" \
    xcodebuild "$what" -project WittyMedia.xcodeproj -scheme "$scheme" -destination "platform=$system,id=$device" \
    -derivedDataPath "${FORGET_CHECK_DERIVED:-DerivedData/forget-check}" -resultBundlePath "$WORK/$log.xcresult" -collect-test-diagnostics never \
    CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="" "$@" >"$WORK/$log.log" 2>&1 || return 1
  # A run that found nothing to run is not a pass.
  [ "$what" != test-without-building ] || grep -q "Executed 1 test, with 0 failures" "$WORK/$log.log"
}
part() { # test name, log name, what it shows
  if run test-without-building "$2" -only-testing:"$scheme/ForgetCheck/$1"; then
    say "ok    $3"
  else
    grep -E 'error: |XCTAssert|failed' "$WORK/$2.log" | sort -u | head -20
    say "FAIL  $3: see $2.log"
    exit 1
  fi
}

# What the app keeps, read and written where it keeps it, with the app not running. `keep` writes
# settings (and a list of servers, given as JSON); `kept` fails unless what is there is as described.
prefs() {
  python3 - "$device" "$BUNDLE" "$@" <<'PY'
import json, os, plistlib, subprocess, sys, time
device, bundle, what = sys.argv[1], sys.argv[2], sys.argv[3]
home = subprocess.check_output(["xcrun", "simctl", "get_app_container", device, bundle, "data"]).decode().strip()
path = os.path.join(home, "Library", "Preferences", bundle + ".plist")
# The system's own keeper of settings answers from what it remembers, and writes that down when it likes:
# it is stopped (it starts again by itself) before the file is read, and after it is written.
def forget_what_the_system_remembers():
    subprocess.call(["xcrun", "simctl", "spawn", device, "launchctl", "stop", "com.apple.cfprefsd.xpc.daemon"])
    time.sleep(1)
forget_what_the_system_remembers()
have = plistlib.load(open(path, "rb")) if os.path.exists(path) else {}
if what == "keep":
    for pair in sys.argv[4:]:
        key, value = pair.split("=", 1)
        if key == "recent":
            servers = json.loads(value)
            for server in servers:
                if "daysAgo" in server:
                    server["lastSeen"] = int((time.time() - 86400 * server.pop("daysAgo")) * 1000)
            have[key] = json.dumps(servers).encode()
        else:
            have[key] = json.loads(value)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    plistlib.dump(have, open(path, "wb"), fmt=plistlib.FMT_BINARY)
    forget_what_the_system_remembers()
    sys.exit(0)
servers = [s["url"] for s in json.loads(have.get("recent", b"[]"))]
wrong = []
for claim in sys.argv[4:]:
    kind, _, value = claim.partition("=")
    if kind == "servers" and servers != [u for u in value.split(",") if u]:
        wrong.append("the servers remembered are %s, not %s" % (servers, value))
    if kind == "none" and [k for k in have if value in k]:
        wrong.append("still kept for %s: %s" % (value, sorted(k for k in have if value in k)))
    if kind == "has" and value not in have:
        wrong.append("%s isn't kept: %s" % (value, sorted(have)))
    if kind == "hasnt" and value in have:
        wrong.append("%s is still kept" % value)
logos = os.path.join(home, "Library", "Caches", "logos")
if "nologos" in sys.argv[4:] and os.path.isdir(logos) and os.listdir(logos):
    wrong.append("logos are still kept: %s" % os.listdir(logos))
for line in wrong:
    print("      " + line)
sys.exit(1 if wrong else 0)
PY
}
kept() { # what it shows, then the claims
  local shows="$1"
  shift
  if prefs kept "$@" | tee -a "$WORK/report.txt"; then say "ok    $shows"; else say "FAIL  $shows"; exit 1; fi
}

run build-for-testing build || { grep -E ' error: |\*\* ' "$WORK/build.log" | sort -u | head -30; say "FAIL  building the app and the check: see build.log"; exit 1; }
say "ok    the app and the check are built for the $kind simulator"

part testSignInToBoth both "both servers are remembered, with the time each was last reached, and the $kind is signed in to the second"
# Something of each server's to find afterwards: a theme chosen on this device, and a top menu.
prefs keep "theme.$a=\"midnight\"" "topMenu.$a.owner=[1,2]" "theme.$b=\"paper\"" "topMenu.$b.owner=[3]"
part testRemoveTheOther other "Manage servers removes the server that isn't in use, and the one in use stays signed in"
kept "on disk, everything kept for the removed server is gone and the other's is all there" \
  "servers=$b" "none=$a" "has=theme.$b" "has=topMenu.$b.owner" "has=server"
part testRemoveTheOneInUse in-use "removing the server in use asks first, signs out, has the server end the sign-in, and goes back to the list of servers"
kept "on disk, nothing of either server is left" "servers=" "none=$a" "none=$b" "hasnt=server" nologos
part testRemoveFromTheList list "the list of servers: removing by $([ "$kind" = iPhone ] && echo "a swipe, Edit and the card's menu, each with Undo, and Remove all in Manage servers" || echo "the card's menu, with focus going to the card that is left, and Remove all in Manage servers")"
kept "on disk, nothing of either server is left" "servers=" "none=$a" "none=$b" nologos

# A list as an older version kept it: no times, and one server in it twice (it moved). And settings left
# under the address it moved from, and under one nothing remembers.
old=http://10.255.0.1:9797; new=http://10.255.0.2:9797; shed=http://10.255.0.9:9797; stray=http://10.255.0.77:9797
prefs keep "recent=[{\"url\":\"$new\",\"name\":\"Home\",\"serverId\":\"home\",\"publicKey\":\"S0VZ\"},{\"url\":\"$old\",\"name\":\"Home\",\"serverId\":\"home\",\"publicKey\":\"S0VZ\",\"brandLogo\":\"v1\"},{\"url\":\"$shed\",\"name\":\"Shed\",\"serverId\":\"shed\",\"daysAgo\":100}]" \
  "theme.$old=\"paper\"" "topMenu.$old.owner=[4]" "theme.$shed=\"light\"" "theme.$stray=\"oled\"" "topMenu.$stray.owner=[9]"
part testAnOldList old-list "a list from an older version shows a server that was in it twice once, with no time made up, and Manage servers removes the one not reached for 90 days after naming it"
kept "on disk, the two entries are one, what was kept under its old address followed it, and what nothing owned or was removed is gone" \
  "servers=$new" "has=theme.$new" "has=topMenu.$new.owner" "none=$old" "none=$stray" "none=$shed"

# The first server's address, remembered with another key: what a reinstall looks like.
prefs keep "recent=[{\"url\":\"$a\",\"name\":\"Before\",\"serverId\":\"before\",\"publicKey\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\",\"fingerprint\":\"0000-0000-0000\"},{\"url\":\"$shed\",\"name\":\"Shed\",\"serverId\":\"shed\"}]" \
  "theme.$a=\"midnight\"" "theme.$shed=\"light\""
part testAChangedServer changed "a remembered address answering with another key shows the warning, explains a reinstall, and Remove the old server forgets it"
kept "on disk, the old server and what was kept for it are gone, and the other is as it was" "servers=$shed" "none=$a" "has=theme.$shed"

say "All of it passed, in the $(xcrun simctl list devices | grep "$device" | sed -E 's/^ +//; s/ \(.*//') simulator."
