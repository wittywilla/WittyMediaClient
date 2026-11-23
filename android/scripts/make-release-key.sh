#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
# Makes the Android release key, ONCE, and (with --upload) gives it to GitHub as the android-release environment's
# secrets. Every Android release is signed with this key from then on, and Android installs an update over the app only
# when the key is the same: keep the folder it makes safe, with a copy somewhere else (a USB stick, a password manager).
# If it is lost, no later version can update an installed app: everyone would have to uninstall once again.
#
#   bash android/scripts/make-release-key.sh <folder for the key, outside any repository> [--upload]
#
# It needs keytool (any Java) and openssl; --upload needs gh signed in as the repository's owner. It never prints the
# password, never writes inside a git repository, and refuses to replace a key that is already there.
# Full steps: docs/ANDROID-SIGNING.md.
set -euo pipefail

repo=${WMC_REPO:-wittywilla/WittyMediaClient}
env_name=android-release
alias_name=wittymediaclient
dir=${1:?usage: make-release-key.sh <folder outside any repository> [--upload]}
upload=0
[ "${2:-}" = --upload ] && upload=1

command -v keytool >/dev/null || { echo "keytool isn't installed: install any Java (on Ubuntu: sudo apt install default-jdk-headless)."; exit 1; }
command -v openssl >/dev/null || { echo "openssl isn't installed."; exit 1; }

# Not inside a repository: any folder up the way with a .git (a folder, or a worktree's file) counts. Checked before
# the folder is made, and without git itself, which can refuse to look at another user's checkout.
up=$(realpath -m "$dir")
while :; do
	if [ -e "$up/.git" ]; then
		echo "$dir is inside a git repository ($up). The key must never be committed: choose a folder outside every repository."
		exit 1
	fi
	[ "$up" = / ] && break
	up=$(dirname "$up")
done
mkdir -p "$dir"
dir=$(cd "$dir" && pwd)
store=$dir/wittymediaclient-release.p12
if [ -e "$store" ]; then
	echo "$store is already there. This key is permanent and is never made again; to send it to GitHub again, run with --upload-only."
	[ "${2:-}" = --upload-only ] || exit 1
	upload=1
else
	umask 077
	openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-40 >"$dir/password.txt"
	pw=$(cat "$dir/password.txt")
	keytool -genkeypair -storetype PKCS12 -keystore "$store" -alias "$alias_name" -keyalg RSA -keysize 4096 \
		-validity 18250 -dname "CN=WittyMediaClient, O=WittyWilla" -storepass "$pw" -keypass "$pw" </dev/null >/dev/null
	unset pw
	cat >"$dir/README.txt" <<-EOF
		WittyMediaClient's Android release key. Every Android release is signed with it, and Android only installs an
		update over the app when the key is the same. Keep this folder, and a copy somewhere else. Never commit it.
		  wittymediaclient-release.p12   the key (PKCS12, alias $alias_name)
		  password.txt                   its password (the store and the key have the same one)
		On GitHub it is the "$env_name" environment's secrets ANDROID_RELEASE_KEYSTORE (the .p12 in base64) and
		ANDROID_RELEASE_KEYSTORE_PASSWORD. See docs/ANDROID-SIGNING.md in WittyMediaClient.
	EOF
	base64 -w0 "$store" >"$dir/keystore-base64.txt" 2>/dev/null || base64 "$store" | tr -d '\n' >"$dir/keystore-base64.txt"
	echo "Made the release key in $dir"
fi

echo "Its certificate's SHA-256 fingerprint (public; every release's APKs show this one):"
keytool -list -v -keystore "$store" -storepass:file "$dir/password.txt" -alias "$alias_name" </dev/null | grep -m1 'SHA256:' | sed 's/^[[:space:]]*//'

if [ "$upload" = 1 ]; then
	gh=$(command -v gh || command -v gh.exe || true)
	[ -n "$gh" ] || { echo "gh isn't installed here: add the secrets by hand (docs/ANDROID-SIGNING.md)."; exit 1; }
	# The environment, usable only by version tags (v*), so no branch's workflow can read the key.
	"$gh" api -X PUT "repos/$repo/environments/$env_name" --input - >/dev/null <<-EOF
		{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
	EOF
	"$gh" api -X POST "repos/$repo/environments/$env_name/deployment-branch-policies" -f name='v*' -f type=tag >/dev/null 2>&1 || true
	"$gh" secret set ANDROID_RELEASE_KEYSTORE -R "$repo" -e "$env_name" <"$dir/keystore-base64.txt"
	"$gh" secret set ANDROID_RELEASE_KEYSTORE_PASSWORD -R "$repo" -e "$env_name" <"$dir/password.txt"
	echo "GitHub has the key: the $env_name environment of $repo, for v* tags only."
	"$gh" secret list -R "$repo" -e "$env_name"
fi
echo
echo "Now back up $dir (a USB stick, a password manager). It is never made again."
