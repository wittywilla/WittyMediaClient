#!/bin/sh
# Starts WittyMedia in the system's Electron. The one it was built for comes first. The ports tree
# retires each Electron within months, so if that one has gone, the newest there is takes over.
#
# On the other platforms, these settings are switched off inside the app's own copy of Electron.
# This copy is shared, so they're cleared here instead.
unset ELECTRON_RUN_AS_NODE NODE_OPTIONS NODE_PATH ELECTRON_ENABLE_LOGGING ELECTRON_LOG_FILE

electron=/usr/local/share/%%ELECTRON%%/electron
if [ ! -x "$electron" ]; then
	electron=$(ls -d /usr/local/share/electron[0-9]*/electron 2>/dev/null | sort -V | tail -n 1)
fi
if [ -z "$electron" ] || [ ! -x "$electron" ]; then
	echo "WittyMedia needs Electron. Install it with: pkg install %%ELECTRON%%" >&2
	exit 1
fi

# This Electron plays sound through a sound server, and a video it can't open sound for never
# starts its clock. FreeBSD doesn't run one by default, so without one this starts sndio's, for
# this user. With no sound card at all there's nothing to open, and the picture plays silently.
sound_server_running() {
	pgrep -q -x sndiod || pgrep -q -x pulseaudio || pgrep -q -x pipewire
}

no_sound=
if ! ls /dev/dsp* >/dev/null 2>&1; then
	no_sound=--disable-audio-output
elif ! sound_server_running; then
	sndiod 2>/dev/null
	sleep 0.2
	sound_server_running || no_sound=--disable-audio-output
fi

exec "$electron" /usr/local/share/wittymedia/app.asar $no_sound "$@"
