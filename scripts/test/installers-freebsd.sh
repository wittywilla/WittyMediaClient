#!/usr/bin/env bash
# Proves the FreeBSD package for real, in a throwaway FreeBSD virtual machine. From a bare system:
# install, with only what the package declares; the app opened on a virtual screen as an ordinary
# person. Then, with Electron kept: install, upgrade, the uninstaller's questions, removal, and a
# listing of the file system from before and after that must match.
# Runs where QEMU can use KVM: apt install qemu-system-x86 sshpass.
#
#   scripts/test/installers-freebsd.sh <folder> [15.1 14.4 ...]
#
# The folder holds wittymediaclient-<version>-freebsd-amd64.pkg, and upgrade/ the same at 9.9.9.
# Build them on FreeBSD, in desktop/, with:
#   npm run package:freebsd
#   and the second with "version" set to 9.9.9 in package.json.
# Writes each run's listing to <folder>/results/. The image is kept in ~/.cache.
set -uo pipefail

PKGS="$(cd "${1:?folder with packages}" && pwd)"; shift
RELEASES=("$@"); [ ${#RELEASES[@]} -gt 0 ] || RELEASES=(15.1)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS="$PKGS/results"; mkdir -p "$RESULTS"
CACHE="$HOME/.cache/wittymediaserver-freebsd"; mkdir -p "$CACHE"
FAILED=0

for REL in "${RELEASES[@]}"; do
  log="$RESULTS/freebsd-$REL.log"; : > "$log"
  echo "==> FreeBSD $REL"
  RAW="$CACHE/FreeBSD-$REL-RELEASE-amd64-BASIC-CI.raw"
  if [ ! -f "$RAW" ]; then
    BASE="https://download.freebsd.org/releases/CI-IMAGES/$REL-RELEASE/amd64/Latest/FreeBSD-$REL-RELEASE-amd64-BASIC-CI"
    curl -fsSL -o "$RAW.xz" "$BASE.raw.xz" </dev/null || curl -fsSL -o "$RAW.xz" "$BASE-ufs.raw.xz" </dev/null || { echo "   can't download the image"; FAILED=1; continue; }
    xz -d "$RAW.xz"
  fi
  DISK="$(mktemp -d)/disk.qcow2"
  qemu-img create -q -f qcow2 -F raw -b "$RAW" "$DISK" 30G
  PORT=$((23000 + RANDOM % 1000))
  QEMU="qemu-system-x86_64"; [ -w /dev/kvm ] || QEMU="sudo qemu-system-x86_64"
  $QEMU -enable-kvm -cpu host -smp 4 -m 6144 -nographic -serial null -monitor none \
    -drive "file=$DISK,if=virtio,format=qcow2" -netdev "user,id=n,hostfwd=tcp:127.0.0.1:$PORT-:22" -device virtio-net-pci,netdev=n \
    >/dev/null 2>&1 </dev/null &
  VM=$!
  SSH=(sshpass -p '' ssh -p "$PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ServerAliveInterval=15 root@127.0.0.1)
  SCP=(sshpass -p '' scp -P "$PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
  for _ in $(seq 1 90); do "${SSH[@]}" -n true 2>/dev/null && break; sleep 3; done
  "${SSH[@]}" -n 'mkdir -p /pkgs/upgrade /test' >>"$log" 2>&1
  "${SCP[@]}" "$PKGS"/wittymediaclient-*-freebsd-amd64.pkg root@127.0.0.1:/pkgs/ </dev/null >>"$log" 2>&1
  "${SCP[@]}" "$PKGS"/upgrade/wittymediaclient-*-freebsd-amd64.pkg root@127.0.0.1:/pkgs/upgrade/ </dev/null >>"$log" 2>&1
  "${SCP[@]}" "$HERE/app-smoke.mjs" "$HERE/app-close.mjs" root@127.0.0.1:/test/ </dev/null >>"$log" 2>&1

  "${SSH[@]}" sh -s >>"$log" 2>&1 <<'SCRIPT'
fail() { echo "FAIL: $*"; exit 1; }
say() { echo; echo "##### $*"; }
export ASSUME_ALWAYS_YES=yes IGNORE_OSVERSION=yes
APP=wittymediaclient
SHARE=/usr/local/share/$APP
pkg=$(ls /pkgs/$APP-*-freebsd-amd64.pkg)
new=$(ls /pkgs/upgrade/$APP-*-freebsd-amd64.pkg)
# What a machine does by itself, so isn't the package's doing.
snapshot() {
  find / -xdev \( -path /proc -o -path /dev -o -path /tmp -o -path /root -o -path /pkgs -o -path /test -o -path /var/log -o -path /var/run -o -path /var/db/pkg -o -path /var/cache -o -path /var/tmp \
    -o -path /var/db/ntp -o -path /var/db/entropy -o -path /var/db/services.db -o -path /var/backups -o -path /var/spool -o -path /usr/local/share/applications/mimeinfo.cache \
    -o -path /usr/local/share/icons/hicolor/icon-theme.cache -o -path /usr/local/share/mime \) -prune -o -print 2>/dev/null | sort
  echo "--- accounts"; cut -d: -f1 /etc/passwd | sort; cut -d: -f1 /etc/group | sort
}
tester() { su -m tester -c "cd /home/tester && HOME=/home/tester $1"; }
open_app() {
  rm -f /tmp/app.log /tmp/net.json
  tester "DISPLAY=:9 exec $APP $2 --remote-debugging-port=9333 --remote-allow-origins='*' --log-net-log=/tmp/net.json" >/tmp/app.log 2>&1 &
  node /test/app-smoke.mjs 9333 "$1" || { tail -n 30 /tmp/app.log; fail "the app didn't open"; }
  ps -axww -o args | grep -- "--type=renderer" | grep -v grep | grep -q -- --no-sandbox && fail "renderers run without the sandbox"
  node /test/app-close.mjs 9333 || fail "couldn't ask it to quit"
  for _ in $(seq 1 30); do pgrep -f $SHARE/app.asar >/dev/null || break; sleep 1; done
  pgrep -f $SHARE/app.asar >/dev/null && fail "it didn't quit when asked"
  sleep 1
  pgrep -x sndiod >/dev/null && fail "the sound server it started outlived it"
  [ -s /tmp/net.json ] || fail "no network log to read"
  hosts=$(grep -oE 'https?://[a-zA-Z0-9.-]+' /tmp/net.json | sort -u | grep -vE '://(127\.|localhost|10\.|172\.|192\.168\.|a-made-up-server)' || true)
  [ -z "$hosts" ] || { echo "$hosts"; fail "it reached outside addresses"; }
  echo "reached nothing outside"
}

say "getting ready"
freebsd-version; uname -m
ping -c1 -t5 pkg.freebsd.org >/dev/null 2>&1 || dhclient vtnet0 >/dev/null 2>&1
pkg bootstrap -y 2>&1 | tail -n 1
pkg install -y sudo node22 xorg-vfbserver > /tmp/pkg.txt 2>&1 || { tail -n 15 /tmp/pkg.txt; fail "the test's own tools"; }
pw useradd tester -m -s /bin/sh -c tester || fail "no test account"
echo 'tester ALL=(ALL) NOPASSWD: /usr/local/sbin/pkg' >> /usr/local/etc/sudoers
Xvfb :9 -screen 0 1920x1080x24 >/dev/null 2>&1 &
sleep 2
# A stand-in sound card, so the launcher starts its sound server and the test can see it stop.
kldload snd_dummy 2>/dev/null; ls /dev/dsp* 2>/dev/null

say "from a bare system: install with only what the package declares: $pkg"
pkg install -y "$pkg" > /tmp/out 2>&1 || { tail -n 20 /tmp/out; fail "installing"; }
tail -n 4 /tmp/out
pkg info -e $APP || fail "not installed"
pkg info -d $APP
pkg info -l $APP
command -v $APP || fail "no command"

say "nothing it installs is writable by everyone"
bad=$(find /usr/local/bin/$APP $SHARE /usr/local/share/applications/$APP.desktop /usr/local/share/icons/hicolor/512x512/apps/$APP.png -perm -o+w ! -type l)
[ -z "$bad" ] || { echo "$bad"; fail "world-writable files"; }

say "the menu entry"
cat /usr/local/share/applications/$APP.desktop
grep -q "^Exec=$APP" /usr/local/share/applications/$APP.desktop || fail "the menu entry doesn't start it"
[ -f /usr/local/share/icons/hicolor/512x512/apps/$APP.png ] || fail "no icon"

say "it really opens, as an ordinary person, on a virtual screen"
open_app /tmp/opened.png ""
echo "--- what it wrote in the home folder"
(cd /home/tester && find . -maxdepth 2 | sort)
[ -d /home/tester/.config/WittyMediaClient ] || fail "the data folder isn't where it should be"
grep -q 'FreeBSD' /home/tester/.config/WittyMediaClient/logs/client.log || fail "its log doesn't say FreeBSD"

say "pkg delete says what's left, and takes nothing of anyone's"
pkg delete -y $APP > /tmp/out 2>&1 || { cat /tmp/out; fail "removing"; }
cat /tmp/out
grep -q 'has been removed' /tmp/out || fail "doesn't say what's left in the home folder"
[ -d /home/tester/.config/WittyMediaClient ] || fail "removing took the settings"
[ ! -e /usr/local/bin/$APP ] || fail "the command stayed"
[ ! -e $SHARE ] || fail "its folder stayed"
pkg info -e electron42 || fail "Electron went, which it wasn't asked to"

say "the documented command removes what's in the home folder"
tester 'rm -rf ~/.config/WittyMediaClient ~/.config/WittyMedia'
(cd /home/tester && find . -mindepth 1 -maxdepth 3 | sort)
rm -rf /home/tester/.cache /home/tester/.config /home/tester/.local /home/tester/.pki /home/tester/.sndio

say "snapshot before"
snapshot > /tmp/before.txt
wc -l /tmp/before.txt

say "install, with data from before, and something of someone else's beside it"
pkg install -y "$pkg" > /tmp/out 2>&1 || { tail -n 20 /tmp/out; fail "installing"; }
mkdir -p /home/tester/.config/WittyMediaClient /home/tester/.config/WittyMedia /home/tester/.config/SomeoneElse /srv/media
echo '{"server":"http://a-made-up-server:9797"}' > /home/tester/.config/WittyMediaClient/state.json
echo old > /home/tester/.config/WittyMedia/state.json
echo theirs > /home/tester/.config/SomeoneElse/keep.txt
echo film > "/srv/media/A Made-Up Film.mkv"
chown -R tester /home/tester/.config

say "upgrade: $new"
pkg install -y "$new" > /tmp/out 2>&1 || { tail -n 20 /tmp/out; fail "upgrading"; }
tail -n 3 /tmp/out
[ "$(pkg query %v $APP)" = 9.9.9 ] || fail "still the old version"
[ -f /home/tester/.config/WittyMediaClient/state.json ] || fail "the upgrade lost the settings"
open_app "" ""
grep -q a-made-up-server /home/tester/.config/WittyMediaClient/state.json || fail "the app lost the settings on upgrade"

say "--uninstall --dry-run lists it and changes nothing"
tester "$APP --uninstall --dry-run" </dev/null | tee /tmp/dry.txt
grep -q 'Dry run: nothing was removed' /tmp/dry.txt || fail "no dry run"
grep -q '/home/tester/.config/WittyMediaClient' /tmp/dry.txt || fail "the list hasn't the data folder"
pkg info -e $APP || fail "a dry run removed it"

say "--uninstall with no to both changes nothing, and says so"
printf 'no\nno\n' | tester "$APP --uninstall" | tee /tmp/no.txt
pkg info -e $APP || fail "no meant no, for the program"
[ -f /home/tester/.config/WittyMediaClient/state.json ] || fail "no meant no, for the settings"
grep -q "What's left" /tmp/no.txt || fail "doesn't report what's left"

say "--uninstall, program only: the data stays, and it says how to remove it"
printf 'yes\nno\n' | tester "$APP --uninstall" | tee /tmp/prog.txt
pkg info -e $APP && fail "the program stayed"
[ -f /home/tester/.config/WittyMediaClient/state.json ] || fail "took the settings it was told to leave"
grep -q 'rm -rf.*WittyMediaClient' /tmp/prog.txt || fail "doesn't say how to remove the rest"
grep -q 'Electron' /tmp/prog.txt || fail "doesn't say Electron stays"

say "--uninstall again, both: everything of the app's goes, and nothing else"
pkg install -y "$pkg" > /tmp/out 2>&1 || { tail -n 20 /tmp/out; fail "installing again"; }
printf 'yes\nyes\n' | tester "$APP --uninstall" | tee /tmp/both.txt
pkg info -e $APP && fail "the program stayed"
[ ! -e /home/tester/.config/WittyMediaClient ] || fail "the data stayed"
[ ! -e /home/tester/.config/WittyMedia ] || fail "the old data stayed"
[ -f /home/tester/.config/SomeoneElse/keep.txt ] || fail "TOOK SOMETHING OF SOMEONE ELSE'S"
[ -f "/srv/media/A Made-Up Film.mkv" ] || fail "A FILM WAS DELETED"
pkg info -e electron42 || fail "Electron went, which it wasn't asked to"

say "the snapshot after"
rm -rf /home/tester/.cache /home/tester/.config /home/tester/.local /home/tester/.pki /home/tester/.sndio /srv/media
snapshot > /tmp/after.txt
if ! diff -u /tmp/before.txt /tmp/after.txt > /tmp/diff.txt; then
  cat /tmp/diff.txt
  fail "something was left behind or changed"
fi
echo "NOTHING LEFT: $(wc -l < /tmp/after.txt) paths before and after are the same"
echo ALLPASSED
SCRIPT
  if tail -n 1 "$log" | grep -q ALLPASSED; then
    echo "   passed: $log"
  else
    echo "   FAILED: $log"
    tail -n 25 "$log"
    FAILED=1
  fi
  kill "$VM" 2>/dev/null; sudo kill "$VM" 2>/dev/null
  rm -rf "$(dirname "$DISK")"
done
exit $FAILED
