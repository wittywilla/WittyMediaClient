#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
#
# Downloads and checks a Go module's dependencies, trying again when the network drops: CI runners often see
# sum.golang.org end a stream ("stream error ... INTERNAL_ERROR"), which fails a whole build. The checksum
# database stays on; only the attempt is repeated.
# Usage: go-mod-download.sh <module folder>
set -u
dir="${1:?usage: go-mod-download.sh <module folder>}"
for try in 1 2 3 4; do
  (cd "$dir" && GOWORK=off go mod download) && exit 0
  [ "$try" = 4 ] && break
  echo "go mod download failed (try $try of 4); trying again in $((try * 15)) s" >&2
  sleep $((try * 15))
done
echo "go mod download failed four times" >&2
exit 1
