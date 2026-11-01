#!/bin/sh
# Removes WittyMediaClient from FreeBSD: `wittymediaclient --uninstall`. It says what it found, asks
# about the program and about your own data separately, removes only what's the app's, and says
# what's left. Your servers and what's on them are never touched. Add --dry-run to only see the list.
#
# All of it is in one function, because removing the package removes this file too.

PACKAGE=wittymediaclient
KEPT="settings, saved sign-ins, logs and caches"

ask() {
	printf '%s Type yes to go ahead: ' "$1"
	read -r answer || answer=
	[ "$answer" = yes ]
}

remove_package() {
	if [ "$(id -u)" = 0 ]; then
		pkg delete -y "$PACKAGE"
	elif command -v sudo >/dev/null 2>&1; then
		sudo pkg delete -y "$PACKAGE"
	elif command -v doas >/dev/null 2>&1; then
		doas pkg delete -y "$PACKAGE"
	else
		echo "Removing the program needs an administrator, and this computer has no sudo or doas."
		echo "As root, run: pkg delete $PACKAGE"
		return 1
	fi
}

main() {
	dry_run=0
	[ "${1:-}" = --dry-run ] && dry_run=1

	installed=0
	pkg info -e "$PACKAGE" >/dev/null 2>&1 && installed=1

	# A home folder has to look like one before anything in it is deleted.
	yours=
	case "${HOME:-}" in
		/*) if [ "$HOME" != / ] && [ -d "$HOME" ]; then
				for name in WittyMediaClient WittyMedia; do
					[ -d "$HOME/.config/$name" ] && yours="$yours $HOME/.config/$name"
				done
			fi ;;
	esac

	if [ "$installed" = 0 ] && [ -z "$yours" ]; then
		echo "WittyMediaClient isn't on this computer for your account: there is nothing to remove."
		return 0
	fi

	echo "Found on this computer:"
	echo
	if [ "$installed" = 1 ]; then
		echo "  The program, version $(pkg query %v "$PACKAGE"):"
		pkg info -l "$PACKAGE" | sed -n 's|^[[:space:]]*/|    /|p'
	fi
	if [ -n "$yours" ]; then
		echo "  Your $KEPT:"
		for folder in $yours; do echo "    $folder"; done
	fi
	echo
	echo "Nothing else is touched, including your servers and anything on them."
	echo "Other accounts on this computer keep what they have in their own home folders."
	echo

	if [ "$dry_run" = 1 ]; then
		echo "Dry run: nothing was removed."
		return 0
	fi

	if pgrep -f "/share/$PACKAGE/app.asar" >/dev/null 2>&1; then
		echo "WittyMediaClient is open. Quit it, then run this again."
		return 1
	fi

	take_program=0
	take_data=0
	if [ "$installed" = 1 ] && ask "Remove the program?"; then take_program=1; fi
	if [ -n "$yours" ] && ask "Delete your $KEPT too?"; then take_data=1; fi

	failed=0
	if [ "$take_data" = 1 ]; then
		for folder in $yours; do
			if rm -rf -- "$folder" && [ ! -e "$folder" ]; then echo "Removed $folder"; else echo "Couldn't remove $folder"; failed=1; fi
		done
	fi
	# Last, as it takes this file with it.
	if [ "$take_program" = 1 ]; then
		if remove_package; then echo "Removed the program."; else failed=1; fi
	fi

	echo
	echo "What's left:"
	left=0
	if [ "$installed" = 1 ] && [ "$take_program" = 0 ]; then echo "  The program, as you asked."; left=1; fi
	if [ -n "$yours" ] && [ "$take_data" = 0 ]; then
		left=1
		echo "  Your $KEPT. To remove them later:"
		echo "    rm -rf$yours"
	fi
	if [ "$take_program" = 1 ]; then
		left=1
		echo "  Electron and a font, which pkg installed for this app and other programs may use."
		echo "    To remove them if nothing else needs them: pkg autoremove"
	fi
	if [ -e "${HOME:-/nonexistent}/.sndio" ]; then
		left=1
		echo "  $HOME/.sndio, which the system's sound library keeps for every program."
	fi
	[ "$left" = 1 ] || echo "  Nothing."
	return "$failed"
}

main "$@"
exit $?
