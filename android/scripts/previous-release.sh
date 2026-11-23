#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
# Downloads the newest published release's universal and x86_64 APKs, other than the tag being released, for
# check-upgrade.sh and upgrade-test.sh. Needs gh, with GH_TOKEN and GITHUB_REPOSITORY set (as in a workflow).
#
#   android/scripts/previous-release.sh <folder> [<tag being released, such as v0.6.1>]
#
# Prints the tag it chose, or nothing when there is no earlier release with APKs (the folder is then left empty).
set -euo pipefail
dir=${1:?usage: previous-release.sh <folder> [<current tag>]}
current=${2:-}
repo=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}
mkdir -p "$dir"
for tag in $(gh release list -R "$repo" --exclude-drafts --limit 30 --json tagName,publishedAt \
	--jq 'sort_by(.publishedAt) | reverse | .[].tagName'); do
	[ "$tag" = "$current" ] && continue
	if gh release download "$tag" -R "$repo" -D "$dir" --clobber \
		-p '*-android-universal.apk' -p '*-android-x86_64.apk' >/dev/null 2>&1 && ls "$dir"/*.apk >/dev/null 2>&1; then
		echo "$tag"
		exit 0
	fi
done
echo "::notice::No earlier release has Android APKs to compare with" >&2
