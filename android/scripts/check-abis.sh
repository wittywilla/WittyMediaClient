#!/bin/sh
# Says which processors each APK carries native code for, and fails if a library is missing for one it's meant for.
# A device with no matching library is refused at install or crashes when the library is first used, and nothing
# else would catch a dependency that drops one.
#
# Given Gradle's folder of APKs, it checks all five: the universal APK must carry every library for all four
# processors this app promises, and each processor's own APK must carry them for that processor and no other.
# Given one APK, it checks that one carries all four.
#
#   android/scripts/check-abis.sh app/build/outputs/apk/sideload
set -eu

promised="armeabi-v7a arm64-v8a x86 x86_64"

# One APK, for the processors named: each library it carries must be there for every one of them, and for no other promised one.
check() {
	apk=$1
	shift
	wanted=$*
	echo "$(basename "$apk"), $(wc -c <"$apk" | tr -d ' ') bytes:"
	entries=$(unzip -Z1 "$apk") || {
		echo "  Can't read $apk." >&2
		return 1
	}
	listing=$(printf '%s\n' "$entries" | grep '^lib/.*\.so$' || true)
	libraries=$(printf '%s\n' "$listing" | sed -n 's|^lib/[^/]*/||p' | sort -u)
	if [ -z "$libraries" ]; then
		echo "  No native libraries: this APK runs on any processor."
		return 0
	fi
	bad=0
	for library in $libraries; do
		line="  $library:"
		for abi in $wanted; do
			if printf '%s\n' "$listing" | grep -Fqx "lib/$abi/$library"; then
				line="$line $abi"
			else
				line="$line MISSING-$abi"
				bad=1
			fi
		done
		echo "$line"
	done
	for abi in $(printf '%s\n' "$listing" | sed -n 's|^lib/\([^/]*\)/.*|\1|p' | sort -u); do
		case " $wanted " in *" $abi "*) continue ;; esac
		case " $promised " in
			*" $abi "*)
				echo "  Also carries $abi, which belongs in its own APK." >&2
				bad=1
				;;
			*) echo "  Also carries $abi, which isn't promised." ;;
		esac
	done
	return $bad
}

failed=0
if [ -d "$1" ]; then
	folder=$1
	for abi in universal $promised; do
		apk=
		# -x86- doesn't match -x86_64-.
		for candidate in "$folder"/*-"$abi"-*.apk; do
			if [ -e "$candidate" ]; then apk=$candidate; fi
		done
		if [ -z "$apk" ]; then
			echo "No $abi APK in $folder." >&2
			failed=1
		elif [ "$abi" = universal ]; then
			check "$apk" $promised || failed=1
		else
			check "$apk" "$abi" || failed=1
		fi
	done
else
	check "$1" $promised || failed=1
fi

if [ "$failed" -ne 0 ]; then
	echo "An APK is missing a native library for a processor it's meant for, or carries another's." >&2
	exit 1
fi
