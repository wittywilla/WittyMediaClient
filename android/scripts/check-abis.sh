#!/bin/sh
# Says which processors an APK carries native code for, and fails if any library is missing for one
# of the four this app promises. A device with no matching library is refused at install or
# crashes when the library is first used, and nothing else would catch a dependency that drops one.
#
#   android/scripts/check-abis.sh app/build/outputs/apk/sideload/app-sideload.apk
set -eu

apk=$1
abis="armeabi-v7a arm64-v8a x86 x86_64"
listing=$(unzip -Z1 "$apk" | grep '^lib/.*\.so$' || true)
libraries=$(printf '%s\n' "$listing" | sed -n 's|^lib/[^/]*/||p' | sort -u)
failed=0

if [ -z "$libraries" ]; then
	echo "No native libraries: this APK runs on any processor."
	exit 0
fi

for library in $libraries; do
	line="$library:"
	for abi in $abis; do
		if printf '%s\n' "$listing" | grep -qx "lib/$abi/$library"; then
			line="$line $abi"
		else
			line="$line MISSING-$abi"
			failed=1
		fi
	done
	echo "$line"
done

extra=$(printf '%s\n' "$listing" | sed -n 's|^lib/\([^/]*\)/.*|\1|p' | sort -u | grep -vxE 'armeabi-v7a|arm64-v8a|x86|x86_64' || true)
if [ -n "$extra" ]; then
	echo "Also carried, and not promised: $extra"
fi
if [ "$failed" -ne 0 ]; then
	echo "A native library is missing for a processor this app promises." >&2
	exit 1
fi
