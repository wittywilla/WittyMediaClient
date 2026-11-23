#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
# Installs one APK, gives it some state, installs another over it with "adb install -r" as a user's update does, and
# checks the app's data was kept and the app still opens. Run with one emulator or device attached (adb on PATH).
#
#   android/scripts/upgrade-test.sh <old.apk> <new.apk>
#
# The state: the app is opened, so it writes its own settings (a device name it makes once), and, where adb can be
# root (an emulator's google_apis image), a marker file is put in its data folder and every settings file is
# fingerprinted. After the update, the marker and fingerprints must be unchanged, the first-install time must be the
# same (an uninstall would reset it), the versionCode must be the new one, and the app must open and keep running.
# KEEP_STATE=1 skips the uninstall at the start, so an install that was signed in by hand is updated as it is.
# SAME_VERSION_OK=1 lets the two APKs be the same version (a pull request reinstalls its own build over itself).
# With OUT set, the log and screenshots go in that folder.
set -euo pipefail

old_apk=${1:?usage: upgrade-test.sh <old.apk> <new.apk>}
new_apk=${2:?usage: upgrade-test.sh <old.apk> <new.apk>}
pkg=com.wittywilla.wittymediaclient
out=${OUT:-}
[ -z "$out" ] || mkdir -p "$out"

say() { echo "[upgrade-test] $*"; }
die() { echo "::error::upgrade test: $*"; shot failed; exit 1; }
sh_() { adb shell "$@" </dev/null | tr -d '\r'; }
shot() { [ -z "$out" ] || adb exec-out screencap -p >"$out/$1.png" </dev/null 2>/dev/null || true; }
info() { sh_ dumpsys package "$pkg" | sed -n "s/^ *$1=//p" | head -1; }
code() { info versionCode | cut -d' ' -f1; }
running() { sh_ ps -A 2>/dev/null | grep -q "$pkg" || sh_ ps | grep -q "$pkg"; }
open_app() {
	sh_ am start -W -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p "$pkg" >/dev/null 2>&1 \
		|| sh_ monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
	# A shrunk build's first start is slow on an emulator.
	for _ in $(seq 1 30); do running && break; sleep 1; done
	sleep 12
	running || die "the app isn't running 12 seconds after it was opened"
	if sh_ logcat -d -b crash 2>/dev/null | grep -q "Process: $pkg"; then
		sh_ logcat -d -b crash | tail -40
		die "the app crashed"
	fi
}

adb wait-for-device
for _ in $(seq 1 120); do [ "$(sh_ getprop sys.boot_completed)" = 1 ] && break; sleep 2; done
say "device: $(sh_ getprop ro.product.model), Android $(sh_ getprop ro.build.version.release) (API $(sh_ getprop ro.build.version.sdk))"

# Root lets the test look inside the app's data folder; without it the install-time and versionCode checks still hold.
root=0
if adb root </dev/null >/dev/null 2>&1; then
	sleep 2
	adb wait-for-device
	[ "$(sh_ id -u)" = 0 ] && root=1
fi
say "root: $([ $root = 1 ] && echo yes || echo no)"
data=/data/data/$pkg

if [ "${KEEP_STATE:-0}" != 1 ]; then
	adb uninstall "$pkg" </dev/null >/dev/null 2>&1 || true
	say "installing the old APK: $(basename "$old_apk")"
	r=$(adb install "$old_apk" </dev/null 2>&1 | tr -d '\r'); echo "$r"
	grep -q Success <<<"$r" || die "the old APK didn't install"
	sh_ logcat -c 2>/dev/null || true
	open_app
	shot 1-old-opened
	sh_ am force-stop "$pkg"
fi
old_code=$(code)
first_install=$(info firstInstallTime)
say "installed: versionCode $old_code ($(info versionName)), first installed $first_install"

marker=""
if [ $root = 1 ]; then
	marker="upgrade-test-$(date +%s)-$RANDOM"
	sh_ "mkdir -p $data/files && echo $marker > $data/files/upgrade-test-marker"
	before=$(sh_ "cd $data/shared_prefs && md5sum *.xml" 2>/dev/null || true)
	[ -n "$before" ] || die "the old app wrote no settings when opened"
	say "settings before the update:"; echo "$before"
	sh_ "ls $data/shared_prefs" | sed 's/^/  /'
fi

say "installing the new APK over it with adb install -r: $(basename "$new_apk")"
r=$(adb install -r "$new_apk" </dev/null 2>&1 | tr -d '\r'); echo "$r"
grep -q Success <<<"$r" || die "the new APK didn't install over the old one (an update would fail for users too): $r"

new_code=$(code)
say "now: versionCode $new_code ($(info versionName)), first installed $(info firstInstallTime), updated $(info lastUpdateTime)"
[ "$(info firstInstallTime)" = "$first_install" ] || die "the first-install time changed: the app was reinstalled, not updated"
if [ "${SAME_VERSION_OK:-0}" = 1 ]; then
	[ "$new_code" -ge "$old_code" ] || die "versionCode went from $old_code down to $new_code"
else
	[ "$new_code" -gt "$old_code" ] || die "versionCode went from $old_code to $new_code, not up"
fi

if [ $root = 1 ]; then
	[ "$(sh_ cat $data/files/upgrade-test-marker)" = "$marker" ] || die "the marker in the app's data folder is gone"
	after=$(sh_ "cd $data/shared_prefs && md5sum *.xml" 2>/dev/null || true)
	[ "$after" = "$before" ] || { echo "after:"; echo "$after"; die "the app's settings changed in the update"; }
	say "the marker and every settings file are unchanged"
	sh_ rm -f $data/files/upgrade-test-marker
fi

sh_ logcat -c 2>/dev/null || true
open_app
shot 2-new-opened
say "PASS: $(basename "$new_apk") installed over $(basename "$old_apk") in place, kept the app's data and opens"
