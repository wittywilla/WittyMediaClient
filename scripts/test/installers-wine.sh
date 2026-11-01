#!/usr/bin/env bash
# Proves the Windows setup by really running it, in a throwaway container with Wine: install for one
# person and for everyone, upgrade, uninstall with and without /RemoveData, and the files and registry
# from before and after, to show nothing is left. With "screenshots" it also photographs the wizard
# and answers the uninstaller's question both ways. Wine isn't Windows, so a real Windows has the
# last word: docs/INSTALLING.md lists what to check.
#
#   scripts/test/installers-wine.sh <folder with the setup> [screenshots]
#
# The folder holds wittymediaclient-*-windows-amd64-setup.exe, and upgrade/ the same at a later version.
# Writes its listing to <folder>/results/wine.log, and any photographs to <folder>/results/wizard/.
set -uo pipefail

PKGS="$(cd "${1:?folder with the setup}" && pwd)"
SHOTS="${2:-}"
RESULTS="$PKGS/results"; mkdir -p "$RESULTS"
log="$RESULTS/wine.log"
tag=witty-installer-test-wine

docker build -q -t "$tag" - >"$log" 2>&1 <<'EOF'
FROM debian:trixie-slim
RUN dpkg --add-architecture i386 && apt-get update && apt-get install -y --no-install-recommends \
    wine wine64 wine32:i386 xvfb xauth x11-utils imagemagick xdotool procps file fonts-liberation p7zip-full
EOF
[ $? -eq 0 ] || { echo "FAILED to prepare the image: see $log"; tail -n 20 "$log"; exit 1; }

docker rm -f witty-inst-wine >/dev/null 2>&1
docker run -i --rm --name witty-inst-wine -e SHOTS="$SHOTS" -v "$PKGS:/pkgs" "$tag" bash -s >>"$log" 2>&1 <<'SCRIPT'
set -u
# Wine would otherwise copy shortcuts out to the Linux menus, which is its own doing and not the setup's.
export WINEPREFIX=/root/wine WINEARCH=win64 WINEDEBUG=-all DISPLAY=:99 WINEDLLOVERRIDES=winemenubuilder.exe=d
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
sleep 1
fail() { echo "FAIL: $*"; exit 1; }
say() { echo; echo "##### $*"; }
wineboot -i >/dev/null 2>&1
wineserver -w
APP=WittyMediaClient
setup=$(ls /pkgs/wittymediaclient-*-windows-amd64-setup.exe)
new=$(ls /pkgs/upgrade/wittymediaclient-*-windows-amd64-setup.exe)
C="$WINEPREFIX/drive_c"
# Wine's PowerShell is a stub that says yes to everything, so the setup would believe the app is always
# running. Without it, the setup asks tasklist instead, as it does on a Windows with PowerShell blocked.
rm -f "$C/windows/system32/WindowsPowerShell/v1.0/powershell.exe" "$C/windows/syswow64/WindowsPowerShell/v1.0/powershell.exe"
USERDIR="$C/users/root"
ROAMING="$USERDIR/AppData/Roaming"
MINE="$USERDIR/AppData/Local/Programs/$APP"
EVERYONE="$C/Program Files/$APP"

snapshot() {
  wineserver -w
  # Wine's own bookkeeping isn't the installer's doing.
  (cd "$C" && find . -path ./windows/Installer -prune -o -path ./windows/logs -prune -o -path ./windows/temp -prune \
      -o -path ./users/root/Temp -prune -o -path ./users/root/AppData/Local/Temp -prune -o -print | sort)
  echo "--- registry"
  for f in system.reg user.reg; do
    sed -E 's/^(\[[^]]*\]).*/\1/' "$WINEPREFIX/$f" | grep -Eai 'witty|^"[^"]*witty' | sort
  done
}
reg_has() { grep -aqi "$1" "$WINEPREFIX/system.reg" "$WINEPREFIX/user.reg"; }
# The uninstaller copies itself elsewhere to run and returns at once, so wait for what it started.
uninstall() {
  wine "$1/Uninstall $APP.exe" "${@:2}"
  wineserver -w; sleep 2; wineserver -w
}
run_setup() {
  wine "$@"
  code=$?
  wineserver -w
  return $code
}
leave_data() {
  mkdir -p "$ROAMING/$APP/logs" "$ROAMING/$APP/Cache/Cache_Data" "$ROAMING/$APP/Local Storage/leveldb" "$ROAMING/WittyMedia/logs"
  echo '{}' > "$ROAMING/$APP/state.json"; echo x > "$ROAMING/$APP/logs/client.log"; echo x > "$ROAMING/$APP/Cookies"
  echo x > "$ROAMING/$APP/Cache/Cache_Data/index"; echo x > "$ROAMING/WittyMedia/state.json"
}

say "what's in the setup"
7z l "$setup" | grep -Ei 'nsis|Listing|^Type|uninstall|\.7z|\$' | head -20

say "snapshot before"
snapshot > /tmp/before.txt
wc -l /tmp/before.txt
mkdir -p "$USERDIR/Videos"; echo film > "$USERDIR/Videos/A Made-Up Film.mkv"

say "install just for me, silently: $setup"
run_setup "$setup" /S || fail "install exit $code"
snapshot > /tmp/installed.txt
diff /tmp/before.txt /tmp/installed.txt | grep '^>' | grep -v 'locales/\|Videos' | head -50
[ -f "$MINE/$APP.exe" ] || fail "the app wasn't installed: $(find "$C" -iname "$APP.exe")"
[ -f "$MINE/Uninstall $APP.exe" ] || fail "no uninstaller"
[ -f "$MINE/resources/installed-files.txt" ] || fail "no list of installed files"
[ ! -e "$USERDIR/AppData/Local/wittymediaclient-updater" ] || fail "it left a copy of the setup"
[ -f "$USERDIR/Desktop/$APP.lnk" ] || fail "no desktop shortcut"
find "$C" -name "$APP.lnk" | sed "s|$C/||"
[ -n "$(find "$USERDIR/AppData/Roaming/Microsoft/Windows/Start Menu" "$C/ProgramData/Microsoft/Windows/Start Menu" -name "$APP.lnk" 2>/dev/null)" ] || fail "no Start menu shortcut"
grep -a -A12 'CurrentVersion\\\\Uninstall\\\\' "$WINEPREFIX/user.reg" | grep -aE 'DisplayName|DisplayVersion|UninstallString|QuietUninstall|Publisher' | head -8
reg_has 'DisplayName.*'$APP || fail "no entry in Add or Remove Programs"

say "upgrade in place: $new"
echo mine > "$MINE/my-own-file.txt"
leave_data
run_setup "$new" /S || fail "upgrade exit $code"
grep -a 'DisplayVersion' "$WINEPREFIX/user.reg" | tail -n 1
grep -aq '"DisplayVersion"="9.9.9"' "$WINEPREFIX/user.reg" || fail "still the old version"
[ -f "$MINE/$APP.exe" ] || fail "the upgrade lost the program"
[ -f "$MINE/my-own-file.txt" ] || fail "the upgrade took a file it didn't make"
[ -f "$ROAMING/$APP/state.json" ] || fail "the upgrade took the settings"
[ "$(grep -ac 'DisplayName.*'$APP "$WINEPREFIX/user.reg")" = 1 ] || fail "two entries in Add or Remove Programs"

say "uninstall silently, keeping the settings"
uninstall "$MINE" /S
[ ! -e "$MINE/$APP.exe" ] || fail "the program stayed"
[ ! -e "$MINE/Uninstall $APP.exe" ] || fail "the uninstaller stayed"
[ ! -e "$USERDIR/Desktop/$APP.lnk" ] || fail "the desktop shortcut stayed"
[ -f "$MINE/my-own-file.txt" ] || fail "took a file it didn't make"
[ -f "$ROAMING/$APP/state.json" ] || fail "a keep-data uninstall took the settings"
[ -f "$ROAMING/WittyMedia/state.json" ] || fail "a keep-data uninstall took the old folder"
reg_has 'DisplayName.*'$APP && fail "the Add or Remove Programs entry stayed"
find "$MINE" | sed "s|$C/||"
rm -f "$MINE/my-own-file.txt"; rmdir "$MINE" 2>/dev/null

say "install again, for full removal, with startup entries as if the app had made them"
run_setup "$setup" /S || fail "reinstall exit $code"
wine reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' /v "$APP" /d 'C:\x.exe' /f >/dev/null
wine reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' /v "electron.app.$APP" /d 'C:\x.exe' /f >/dev/null
wine reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' /v 'SomeoneElse' /d 'C:\y.exe' /f >/dev/null
wineserver -w

say "uninstall silently, removing the settings"
uninstall "$MINE" /S /RemoveData
[ ! -e "$MINE" ] || { find "$MINE"; fail "the program's folder stayed"; }
[ ! -e "$ROAMING/$APP" ] || fail "the settings stayed"
[ ! -e "$ROAMING/WittyMedia" ] || fail "the folder of the old name stayed"
[ -f "$USERDIR/Videos/A Made-Up Film.mkv" ] || fail "A FILM WAS DELETED"
grep -aq "\"$APP\"=" "$WINEPREFIX/user.reg" && fail "the startup entry stayed"
grep -aq "electron.app.$APP" "$WINEPREFIX/user.reg" && fail "the other startup entry stayed"
grep -aq '"SomeoneElse"=' "$WINEPREFIX/user.reg" || fail "took someone else's startup entry"
wine reg delete 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' /v 'SomeoneElse' /f >/dev/null
wineserver -w

say "snapshot after"
snapshot > /tmp/after.txt
diff -u /tmp/before.txt /tmp/after.txt | grep -v 'Videos' > /tmp/d.txt
if grep -Eq '^[+-][^+-]' /tmp/d.txt; then cat /tmp/d.txt; fail "something was left behind"; fi
echo "NOTHING LEFT: $(wc -l < /tmp/after.txt) paths and registry keys, before and after the same"

say "for everyone, silently"
run_setup "$setup" /S /allusers || fail "machine install exit $code"
[ -f "$EVERYONE/$APP.exe" ] || fail "not in Program Files: $(find "$C" -name "$APP.exe")"
reg_has 'DisplayName.*'$APP || fail "no entry in Add or Remove Programs"
grep -aq "DisplayName.*$APP" "$WINEPREFIX/system.reg" || fail "the entry isn't for everyone"
find "$C" -name "$APP.lnk" | sed "s|$C/||"
leave_data
uninstall "$EVERYONE" /S /allusers
[ ! -e "$EVERYONE" ] || { find "$EVERYONE"; fail "the program stayed in Program Files"; }
[ -f "$ROAMING/$APP/state.json" ] || fail "a keep-data uninstall took the settings"

run_setup "$setup" /S /allusers || fail "machine reinstall exit $code"
uninstall "$EVERYONE" /S /allusers /RemoveData
[ ! -e "$ROAMING/$APP" ] || fail "the settings stayed"
snapshot > /tmp/after2.txt
diff -u /tmp/before.txt /tmp/after2.txt | grep -v 'Videos' > /tmp/d2.txt
if grep -Eq '^[+-][^+-]' /tmp/d2.txt; then cat /tmp/d2.txt; fail "something was left behind by the for-everyone install"; fi
echo "NOTHING LEFT after the for-everyone install either"

say "a file in use stops the uninstaller before it removes anything"
run_setup "$setup" /S || fail "install exit $code"
(cd "$MINE" && wine cmd /c "ping -n 40 127.0.0.1 >> LICENSES.chromium.html") >/dev/null 2>&1 &
holder=$!
sleep 6
wine "$MINE/Uninstall $APP.exe" /S
sleep 15
if [ -f "$MINE/$APP.exe" ] && [ -f "$MINE/resources/app.asar" ]; then
  echo "nothing was removed"
else
  fail "it removed files although one was in use"
fi
reg_has 'DisplayName.*'$APP || fail "the Add or Remove Programs entry went, though the program is still there"
wait "$holder" 2>/dev/null
wineserver -w
uninstall "$MINE" /S
[ ! -e "$MINE" ] || { find "$MINE"; fail "it wouldn't uninstall afterwards"; }

if [ -n "${SHOTS:-}" ]; then
  mkdir -p /pkgs/results/wizard
  shoot() { import -window root "/pkgs/results/wizard/$1.png" 2>/dev/null; }
  # The wizard and its question have the same title, so the number of windows says which is showing.
  windows() { xdotool search --onlyvisible --name "$1" 2>/dev/null | wc -l; }
  wait_windows() {
    for _ in $(seq 1 120); do [ "$(windows "$1")" -ge "$2" ] && { sleep 2; return 0; }; sleep 1; done
    shoot stuck; fail "never saw $2 of the window called $1"
  }
  finish() { timeout 60 wineserver -w || { echo "(closing what was still open)"; wineserver -k; }; sleep 2; }
  by_hand() { # the answer to the question: y or n. Photographs it if given a name
    wine "$MINE/Uninstall $APP.exe" >/dev/null 2>&1 &
    wait_windows "$APP Uninstall" 1
    [ -n "${2:-}" ] && shoot "$2-uninstall-start"
    xdotool key Return
    wait_windows "$APP Uninstall" 2
    [ -n "${2:-}" ] && shoot "$2-uninstall-question"
    xdotool key "$1"
    sleep 5
    [ -n "${2:-}" ] && shoot "$2-uninstall-end"
    xdotool key Return
    finish
  }

  say "photographing the wizard"
  wine "$setup" >/dev/null 2>&1 &
  wait_windows "$APP Setup" 1
  shoot 1-who-is-it-for
  xdotool key Return; sleep 4; shoot 2-where
  xdotool key Return
  for _ in $(seq 1 180); do [ -f "$MINE/Uninstall $APP.exe" ] && break; sleep 1; done
  sleep 10; shoot 3-finished
  # Finished without starting the app: Wine isn't what it's meant to run on.
  xdotool key space; sleep 1
  xdotool key Return
  finish
  [ -f "$MINE/$APP.exe" ] || fail "the wizard didn't install it"

  say "uninstalling by hand, answering No"
  leave_data
  by_hand n 4
  [ -f "$ROAMING/$APP/state.json" ] || fail "answering No still took the settings"
  [ ! -e "$MINE/$APP.exe" ] || fail "the program stayed"
  echo "answering No: the program went and the settings stayed"

  say "uninstalling by hand, answering Yes"
  run_setup "$setup" /S || fail "install exit $code"
  by_hand y 5
  [ ! -e "$ROAMING/$APP" ] || fail "answering Yes left the settings"
  [ ! -e "$MINE/$APP.exe" ] || fail "the program stayed"
  echo "answering Yes: the program and the settings both went"
fi
echo ALLPASSED
SCRIPT
if tail -n 1 "$log" | grep -q ALLPASSED; then
  echo "passed: $log"
else
  echo "FAILED: $log"
  tail -n 40 "$log"
  exit 1
fi
