#!/usr/bin/env bash
# The first check of the Apple apps, for a Mac with Xcode. It signs nothing and installs nothing on a
# real device. It runs WittyKit's tests, builds for Apple TV, iPhone and iPad, then opens each in a
# simulator and takes a picture. Everything it finds goes in apple/build-logs, to send back.
#
#   bash apple/scripts/check-on-mac.sh
set -u
cd "$(dirname "$0")/.."
LOGS="$PWD/build-logs"
rm -rf "$LOGS"
mkdir -p "$LOGS"
REPORT="$LOGS/report.txt"
BUNDLE=com.wittywilla.wittymediaclient
say() { echo "$*" | tee -a "$REPORT"; }

command -v xcodebuild >/dev/null || { echo "Xcode isn't installed: get it from the Mac App Store and open it once."; exit 2; }
command -v xcodegen >/dev/null || { echo "xcodegen isn't installed: run  brew install xcodegen  and then this again."; exit 2; }
say "$(xcodebuild -version | tr '\n' ' ')on macOS $(sw_vers -productVersion)"

if (cd WittyKit && swift test) >"$LOGS/wittykit-tests.log" 2>&1; then say "ok    WittyKit's tests"; else say "FAIL  WittyKit's tests: see wittykit-tests.log"; fi

if ! xcodegen generate >"$LOGS/xcodegen.log" 2>&1; then
  say "FAIL  generating the Xcode project: see xcodegen.log"
  exit 1
fi
say "ok    generating the Xcode project"

build() { # scheme, platform name, log name
  if xcodebuild -project WittyMedia.xcodeproj -scheme "$1" -destination "generic/platform=$2" -derivedDataPath DerivedData \
    CODE_SIGNING_ALLOWED=NO build >"$LOGS/$3.log" 2>&1; then
    say "ok    building for $2"
    return 0
  fi
  say "FAIL  building for $2: $(grep -c ' error: ' "$LOGS/$3.log") errors, see $3.log"
  grep ' error: ' "$LOGS/$3.log" | sed 's/^.*apple\///' | sort -u | head -40 | tee -a "$REPORT"
  return 1
}

# The first simulator of this kind, by name. They come with Xcode, or from its Platforms settings.
simulator() {
  xcrun simctl list devices available | grep -E "^ +$1" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

open_in_simulator() { # kind of device, products folder, picture
  local device app
  device=$(simulator "$1")
  if [ -z "$device" ]; then
    say "not run: no $1 simulator. Add one in Xcode's settings, under Platforms."
    return
  fi
  app=$(find "DerivedData/Build/Products/$2" -maxdepth 1 -name '*.app' | head -1)
  if [ -z "$app" ]; then
    say "not run: nothing built in $2 to open on $1"
    return
  fi
  xcrun simctl boot "$device" 2>/dev/null
  xcrun simctl bootstatus "$device" -b >/dev/null 2>&1
  xcrun simctl install "$device" "$app" 2>>"$REPORT"
  xcrun simctl launch "$device" "$BUNDLE" >>"$LOGS/launch.log" 2>&1 || say "FAIL  it didn't start on $1: see launch.log"
  sleep 10
  xcrun simctl io "$device" screenshot "$LOGS/$3.png" >/dev/null 2>&1
  say "ok    opened on $1: $3.png"
  xcrun simctl shutdown "$device" 2>/dev/null
}

if build WittyMedia-tvOS "tvOS Simulator" build-tvos; then open_in_simulator "Apple TV" Debug-appletvsimulator appletv; fi
if build WittyMedia-iOS "iOS Simulator" build-ios; then
  open_in_simulator "iPhone" Debug-iphonesimulator iphone
  open_in_simulator "iPad" Debug-iphonesimulator ipad
fi
build WittyMedia-macOS "macOS" build-macos
if xcodebuild -showsdks | grep -q -- '-sdk xros'; then
  if build WittyMedia-iOS "visionOS Simulator" build-visionos; then open_in_simulator "Apple Vision Pro" Debug-xrsimulator visionpro; fi
else
  say "not run: this Xcode has no visionOS SDK. Add it in Xcode's settings, under Platforms."
fi

echo
echo "Finished. Send the whole folder back: $LOGS"
