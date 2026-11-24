#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
# Checks that new APKs install as an update over the previous release's, before anything is published. Android
# installs an update in place, keeping the sign-in and settings, only when all three hold:
#
#   - the app ID is the same,
#   - the signing certificate is the same,
#   - the versionCode is higher (the same is allowed by adb, but a release must go up).
#
# Every new APK must be signed by the one release key (never "Android Debug"), all with the same certificate and
# versionCode. Releases up to 0.6.0 were signed with a new debug key each time (docs/ANDROID-SIGNING.md), so they can't
# be updated by anything: when the previous release is debug-signed, the change of key is allowed, this once, with a
# warning, and the release notes say to uninstall once.
#
#   android/scripts/check-upgrade.sh <folder of new APKs> [<folder of the previous release's APKs>]
#   android/scripts/check-upgrade.sh --allow-debug-key app/build/outputs/apk/sideload previous/
#
# --allow-debug-key is for pull requests' sideload builds, which have no release key: the versionCode and app ID are
# still checked against the release. With GITHUB_OUTPUT set it writes same_key=true|false (whether the previous
# release was signed with this key), and with UPGRADE_NOTE set it writes the release note for a change of key there.
set -euo pipefail

app_id=com.wittywilla.wittymediaclient
allow_debug=0
if [ "${1:-}" = --allow-debug-key ]; then allow_debug=1; shift; fi
new_dir=${1:?usage: check-upgrade.sh [--allow-debug-key] <new APK folder> [<previous APK folder>]}
old_dir=${2:-}

# aapt2 and apksigner from the newest build tools, or from PATH.
tools=""
if [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME/build-tools" ]; then
	tools=$(ls -d "$ANDROID_HOME"/build-tools/*/ 2>/dev/null | sort -V | tail -1)
fi
aapt2=${tools}aapt2
apksigner=${tools}apksigner
command -v "$aapt2" >/dev/null || { echo "::error::aapt2 not found (set ANDROID_HOME)"; exit 1; }
command -v "$apksigner" >/dev/null || { echo "::error::apksigner not found (set ANDROID_HOME)"; exit 1; }

failed=0
fail() { echo "::error::$*"; failed=1; }

# One APK's facts, as "app id|versionCode|versionName|minSdk|certificate SHA-256|certificate DN|signers".
facts() {
	local apk=$1 badging certs
	badging=$("$aapt2" dump badging "$apk" 2>/dev/null) || { echo "::error::aapt2 can't read $apk" >&2; return 1; }
	certs=$("$apksigner" verify --print-certs "$apk" 2>&1) || { echo "::error::$apk doesn't verify: $certs" >&2; return 1; }
	printf '%s|%s|%s|%s|%s|%s|%s\n' \
		"$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" <<<"$badging")" \
		"$(sed -n "s/^package:.* versionCode='\([0-9]*\)'.*/\1/p" <<<"$badging")" \
		"$(sed -n "s/^package:.* versionName='\([^']*\)'.*/\1/p" <<<"$badging")" \
		"$(sed -n "s/^\(minSdkVersion\|sdkVersion\):'\([0-9]*\)'.*/\2/p" <<<"$badging" | head -1)" \
		"$(grep -m1 'certificate SHA-256 digest' <<<"$certs" | awk '{print $NF}')" \
		"$(grep -m1 'certificate DN' <<<"$certs" | sed 's/.*certificate DN: //')" \
		"$(grep -c 'certificate SHA-256 digest' <<<"$certs")"
}

# Every APK in a folder must agree on app ID, versionCode and certificate; their shared facts go in $folder_facts.
# (Not run in a subshell, so its failures count.)
folder_facts=""
read_folder() {
	local dir=$1 label=$2 apk line first="" count=0 id code name min cert dn signers
	shopt -s nullglob
	for apk in "$dir"/*.apk; do
		line=$(facts "$apk") || { failed=1; continue; }
		IFS='|' read -r id code name min cert dn signers <<<"$line"
		echo "  $label $(basename "$apk"): $id $name (versionCode $code, minSdk $min), $dn, $cert"
		[ "$signers" = 1 ] || fail "$(basename "$apk") has $signers signers; there must be exactly one"
		[ -n "$cert" ] || fail "$(basename "$apk") has no signing certificate"
		if [ -z "$first" ]; then
			first=$line
		elif [ "${line%%|*}" != "${first%%|*}" ] || [ "$(cut -d'|' -f2 <<<"$line")" != "$(cut -d'|' -f2 <<<"$first")" ] \
			|| [ "$(cut -d'|' -f5 <<<"$line")" != "$(cut -d'|' -f5 <<<"$first")" ]; then
			fail "$label APKs disagree: $(basename "$apk") isn't the same app ID, versionCode and certificate as the others"
		fi
		count=$((count + 1))
	done
	[ "$count" -gt 0 ] || fail "no APKs in $dir"
	folder_facts=$first
}

echo "New APKs in $new_dir:"
read_folder "$new_dir" new
new=$folder_facts
IFS='|' read -r new_id new_code new_name _ new_cert new_dn _ <<<"$new"
[ "$new_id" = "$app_id" ] || fail "the app ID is $new_id, not $app_id: Android would install it as another app"
if [[ "$new_dn" == *"CN=Android Debug"* ]]; then
	if [ "$allow_debug" = 1 ]; then
		echo "::notice::These APKs are signed with a debug key (a pull request's build): only the versionCode and app ID are checked"
	else
		fail "the new APKs are signed with a debug key ($new_dn). A release must be signed with the release key: docs/ANDROID-SIGNING.md"
	fi
fi

same_key=false
if [ -n "$old_dir" ]; then
	echo "Previous release's APKs in $old_dir:"
	read_folder "$old_dir" previous
	old=$folder_facts
	IFS='|' read -r old_id old_code old_name _ old_cert old_dn _ <<<"$old"
	[ "$new_id" = "$old_id" ] || fail "the app ID changed from $old_id to $new_id"
	if [ -n "$new_code" ] && [ -n "$old_code" ] && [ "$new_code" -le "$old_code" ]; then
		fail "versionCode $new_code ($new_name) isn't higher than the previous release's $old_code ($old_name): Android refuses to install it over that"
	fi
	if [ "$new_cert" = "$old_cert" ]; then
		same_key=true
		echo "Same signing certificate as $old_name: it installs over it as an update."
	elif [ "$allow_debug" = 1 ] && [[ "$new_dn" == *"CN=Android Debug"* ]]; then
		echo "Signed with this machine's debug key, so the key isn't compared."
	elif [[ "$old_dn" == *"CN=Android Debug"* ]]; then
		echo "::warning::The previous release ($old_name) was signed with a throwaway debug key, which nothing can update. This release moves to the permanent release key: anyone with $old_name or older has to uninstall once, and every update after this installs over the last."
		if [ -n "${UPGRADE_NOTE:-}" ]; then
			cat >"$UPGRADE_NOTE" <<-EOF
				## Android: uninstall the old version once

				Android versions up to $old_name were each signed with a different temporary key, so Android refuses to install this version over them ("App not installed" or "package conflicts with an existing package"). **Uninstall WittyMediaClient once, then install this version.** You'll need to sign in again, once. From this version on, every update installs over the last one and keeps your sign-in and settings.

			EOF
		fi
	else
		fail "the signing certificate changed from $old_cert to $new_cert: Android refuses to install this over $old_name. Every release must be signed with the same release key (docs/ANDROID-SIGNING.md)"
	fi
else
	echo "No previous release given: only these APKs are checked."
fi

[ -z "${GITHUB_OUTPUT:-}" ] || echo "same_key=$same_key" >>"$GITHUB_OUTPUT"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "### Android update check"
		echo "| | version | versionCode | certificate SHA-256 |"
		echo "|---|---|---|---|"
		[ -z "$old_dir" ] || echo "| previous | $old_name | $old_code | \`$old_cert\` ($old_dn) |"
		echo "| new | $new_name | $new_code | \`$new_cert\` ($new_dn) |"
	} >>"$GITHUB_STEP_SUMMARY"
fi
[ "$failed" = 0 ] || { echo "The Android update check failed."; exit 1; }
echo "The Android update check passed."
