#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
# Archives the iPhone and iPad app and the Apple TV app with signing off, and packs each into an IPA that
# AltStore, SideStore and Sideloadly can sign and install. For a Mac with Xcode; the build and release
# workflows run it. The Xcode project has to be there already: `xcodegen generate` in apple/.
#
#   bash apple/scripts/package-ipas.sh <version for the file names> [log folder]
#
# SKIP_ARCHIVE=1 packs and checks the archives already in apple/build, without building them again.
#
# An IPA is a zip whose only top folder is Payload, holding one <App>.app. A sideloading tool signs it
# on install with the user's own Apple ID, so nothing from a signer belongs in it: no provisioning
# profile, and no entitlements, which only a signature carries. `xcodebuild -exportArchive` isn't used,
# because it insists on signing.
#
# It leaves, in apple/build:
#   wittymediaclient-<version>-ios.ipa    iPhone and iPad, one file for both
#   wittymediaclient-<version>-tvos.ipa   Apple TV, with its Top Shelf extension
#   ios-Info.json, tvos-Info.json         each app's Info.plist, for scripts/altstore-source.mjs
#   ios-entitlements.json                 what the iOS target asks for ({} when it asks for nothing)
#   *.xcarchive                           the archives themselves
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?Give the version for the file names, as in: package-ipas.sh 0.5.0}
LOGS=${2:-$PWD/build-logs}
BUNDLE=com.wittywilla.wittymediaclient
OUT=$PWD/build
mkdir -p "$LOGS" "$OUT"

fail() {
  # An annotation on the run when GitHub is running it.
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::error title=IPA::$*"; else echo "FAIL: $*" >&2; fi
  exit 1
}
warn() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::warning title=IPA::$*"; else echo "warning: $*" >&2; fi
}

# project.yml leaves DEVELOPMENT_TEAM empty and sets no CODE_SIGN_STYLE, so these overrides are enough for
# an unsigned archive. -allowProvisioningUpdates is deliberately absent: it would try to sign.
archive() { # scheme, platform, name
  echo "== Archiving $1 for $2"
  rm -rf "$OUT/$3.xcarchive"
  xcodebuild archive \
    -project WittyMedia.xcodeproj -scheme "$1" -configuration Release \
    -destination "generic/platform=$2" -archivePath "$OUT/$3.xcarchive" \
    -skipPackagePluginValidation -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    PROVISIONING_PROFILE_SPECIFIER="" DEVELOPMENT_TEAM="" \
    -quiet >"$LOGS/archive-$3.log" 2>&1 || {
      tail -60 "$LOGS/archive-$3.log"
      fail "Archiving $1 for $2 failed: see archive-$3.log"
    }
}

# The app's folder name comes from the archive (XcodeGen's PRODUCT_NAME is the target name), so it's
# found and not assumed.
pack() { # archive name, ipa name
  local app stage
  app=$(find "$OUT/$1.xcarchive/Products/Applications" -maxdepth 1 -name '*.app' | head -1)
  [ -n "$app" ] || fail "No .app in $1.xcarchive"
  stage=$(mktemp -d)
  mkdir "$stage/Payload"
  # ditto and not cp -R: it keeps symbolic links and permissions as they are.
  ditto "$app" "$stage/Payload/$(basename "$app")"
  # Anything a signer left behind. A profile that isn't the user's makes AltStore refuse the app, and a
  # signature made for someone else's files is only a wrong one.
  find "$stage/Payload" -name 'embedded.mobileprovision' -delete
  find "$stage/Payload" -name '.DS_Store' -delete
  rm -f "$OUT/$2"
  # -y keeps symbolic links as links, -X leaves out the Mac's extra attributes.
  (cd "$stage" && zip -qryX "$OUT/$2" Payload)
  rm -rf "$stage"
  echo "Packed $(basename "$app") into build/$2"
}

# What an installer needs to be true of the file, checked on the file itself.
check() { # ipa name, platform (iPhoneOS or AppleTVOS), device families wanted, name for the Info.json
  local ipa=$OUT/$1 dir tops apps app plist executable families archs
  echo "== Checking $1"
  dir=$(mktemp -d)
  unzip -q "$ipa" -d "$dir"
  tops=$(cd "$dir" && ls -A | tr '\n' ' ')
  [ "$tops" = "Payload " ] || fail "$1: the top of the zip should be Payload alone, and it holds: $tops"
  apps=$(find "$dir/Payload" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
  app=$(find "$dir/Payload" -mindepth 1 -maxdepth 1 -name '*.app' -type d | head -1)
  [ "$apps" = 1 ] && [ -n "$app" ] || fail "$1: Payload should hold one .app and nothing else"
  plist=$app/Info.plist
  [ -f "$plist" ] || fail "$1: no Info.plist in $(basename "$app")"
  value() { plutil -extract "$1" raw -o - "$plist" 2>/dev/null || true; }

  [ "$(value CFBundleIdentifier)" = "$BUNDLE" ] || fail "$1: CFBundleIdentifier is '$(value CFBundleIdentifier)', not $BUNDLE"
  [ -n "$(value CFBundleShortVersionString)" ] || fail "$1: no CFBundleShortVersionString"
  [ -n "$(value CFBundleVersion)" ] || fail "$1: no CFBundleVersion"
  [ -n "$(value MinimumOSVersion)" ] || fail "$1: no MinimumOSVersion"
  [ "$(value CFBundleSupportedPlatforms.0)" = "$2" ] || fail "$1: built for '$(value CFBundleSupportedPlatforms.0)', not $2"
  families=$(plutil -extract UIDeviceFamily json -o - "$plist" 2>/dev/null | tr -d '[] ' || true)
  for family in $3; do
    case ",$families," in *",$family,"*) ;; *) fail "$1: UIDeviceFamily is [$families], without $family" ;; esac
  done

  executable=$app/$(value CFBundleExecutable)
  [ -f "$executable" ] && [ -x "$executable" ] || fail "$1: the program CFBundleExecutable names isn't in the app, or can't be run"
  archs=$(lipo -archs "$executable")
  case " $archs " in *" arm64 "*) ;; *) fail "$1: built for '$archs', and devices need arm64" ;; esac

  [ -z "$(find "$app" -name 'embedded.mobileprovision')" ] || fail "$1: a provisioning profile is still inside"
  # With signing off there should be no signature on the app itself. Parts built by others (a framework
  # from a Swift package) may carry their own, which a sideloading tool replaces.
  [ ! -e "$app/_CodeSignature" ] || warn "$1: the app has a _CodeSignature folder, so something signed it"
  if [ "$2" = iPhoneOS ] && ! plutil -extract CFBundleIcons xml1 -o /dev/null "$plist" 2>/dev/null; then
    warn "$1: the app has no icon of its own (project.yml sets none), so it installs with a blank one"
  fi

  plutil -convert json -o "$OUT/$4-Info.json" "$plist"
  echo "$(basename "$app"): $(value CFBundleShortVersionString) ($(value CFBundleVersion)), $2 $(value MinimumOSVersion) or later, families [$families], $archs, $(wc -c <"$ipa" | tr -d ' ') bytes"
  if [ "$2" = AppleTVOS ]; then
    if [ -n "$(find "$app/PlugIns" -maxdepth 1 -name '*.appex' 2>/dev/null | head -1)" ]; then
      echo "It carries its Top Shelf extension. A signer has to give the app and the extension the same App Group, or the shelf stays empty."
    else
      warn "$1: no PlugIns/*.appex, so the Top Shelf extension isn't embedded"
    fi
  fi
  rm -rf "$dir"
}

if [ -z "${SKIP_ARCHIVE:-}" ]; then
  [ -d WittyMedia.xcodeproj ] || fail "No WittyMedia.xcodeproj: run xcodegen generate in apple/ first"
  archive WittyMedia-iOS iOS WittyMedia-iOS
  archive WittyMedia-tvOS tvOS WittyMedia-tvOS
fi
pack WittyMedia-iOS "wittymediaclient-$VERSION-ios.ipa"
pack WittyMedia-tvOS "wittymediaclient-$VERSION-tvos.ipa"
# One IPA for iPhone (1) and iPad (2). The project also lists Apple Vision Pro (7), which this build isn't for.
check "wittymediaclient-$VERSION-ios.ipa" iPhoneOS "1 2" ios
check "wittymediaclient-$VERSION-tvos.ipa" AppleTVOS "3" tvos

# What the iOS target asks for, from the file XcodeGen writes when project.yml lists entitlements for it.
if [ -f Generated/WittyMedia-iOS.entitlements ]; then
  plutil -convert json -o "$OUT/ios-entitlements.json" Generated/WittyMedia-iOS.entitlements
else
  echo '{}' >"$OUT/ios-entitlements.json"
fi

ls -la "$OUT"/*.ipa
