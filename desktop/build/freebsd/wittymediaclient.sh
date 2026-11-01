#!/bin/sh
# Starts WittyMediaClient in the system's Electron. The one it was built for comes first. The ports
# tree retires each Electron within months, so if that one has gone, the newest there is takes over.
#
# On the other platforms, these settings are switched off inside the app's own copy of Electron.
# This copy is shared, so they're cleared here instead.
unset ELECTRON_RUN_AS_NODE NODE_OPTIONS NODE_PATH ELECTRON_ENABLE_LOGGING ELECTRON_LOG_FILE

if [ "${1:-}" = --uninstall ]; then
	shift
	exec /bin/sh /usr/local/share/wittymediaclient/uninstall.sh "$@"
fi

electron=/usr/local/share/%%ELECTRON%%/electron
if [ ! -x "$electron" ]; then
	electron=$(ls -d /usr/local/share/electron[0-9]*/electron 2>/dev/null | sort -V | tail -n 1)
fi
if [ -z "$electron" ] || [ ! -x "$electron" ]; then
	echo "WittyMediaClient needs Electron. Install it with: pkg install %%ELECTRON%%" >&2
	exit 1
fi

# This Electron plays sound through a sound server, and a video it can't open sound for never
# starts its clock. FreeBSD doesn't run one by default, so without one this starts sndio's for as
# long as the app is open. With no sound card there's nothing to open, and the picture plays silently.
sound_server_running() {
	pgrep -q -x sndiod || pgrep -q -x pulseaudio || pgrep -q -x pipewire
}

no_sound=
sound_server=
if ! ls /dev/dsp* >/dev/null 2>&1; then
	no_sound=--disable-audio-output
elif ! sound_server_running; then
	sndiod -d >/dev/null 2>&1 &
	sound_server=$!
	sleep 0.2
	if ! kill -0 "$sound_server" 2>/dev/null; then
		sound_server=
		no_sound=--disable-audio-output
	fi
fi

if [ -z "$sound_server" ]; then
	exec "$electron" /usr/local/share/wittymediaclient/app.asar $no_sound "$@"
fi

# Nothing of the app's stays running after it, whichever way it ends.
"$electron" /usr/local/share/wittymediaclient/app.asar "$@" &
app=$!
trap 'kill "$app" 2>/dev/null' HUP INT TERM
while kill -0 "$app" 2>/dev/null; do
	wait "$app"
	status=$?
done
kill "$sound_server" 2>/dev/null
exit "${status:-0}"
