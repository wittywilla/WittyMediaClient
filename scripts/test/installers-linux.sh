#!/usr/bin/env bash
# Proves the Linux packages for real, in throwaway containers. From a bare system: install, with
# only what the package declares; every shared library resolved; the app opened on a virtual screen
# with its sandbox on. Then, with those libraries kept: install, upgrade, remove, purge, and a
# snapshot of the file system from before and after to show nothing is left.
#
#   scripts/test/installers-linux.sh <folder with packages> [debian:trixie-slim ubuntu:26.04 fedora:43 archlinux:latest ...]
#
# The folder holds wittymediaclient-<version>-linux-amd64.{deb,rpm,pacman}, and upgrade/ the same at 9.9.9.
# Build them in desktop/ with:
#   npx electron-builder --linux
#   npx electron-builder --linux deb rpm pacman -c.extraMetadata.version=9.9.9 -c.directories.output=out-upgrade
#
# Runs where Docker runs Linux containers. Needs Node 22 or newer on the host, lent to the containers
# to drive the app. Writes each run's listings to <folder>/results/.
set -uo pipefail

PKGS="$(cd "${1:?folder with packages}" && pwd)"; shift
IMAGES=("$@"); [ ${#IMAGES[@]} -gt 0 ] || IMAGES=(debian:trixie-slim ubuntu:26.04 fedora:43)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE="$(readlink -f "$(command -v node)")"
RESULTS="$PKGS/results"; mkdir -p "$RESULTS"
FAILED=0

# What a machine does by itself, so isn't the package's doing.
SNAPSHOT='find / -xdev \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /tmp -o -path /pkgs -o -path /test -o -path /var/log -o -path /var/cache -o -path /var/tmp \
  -o -path /var/lib/dpkg -o -path /var/lib/apt -o -path /var/lib/rpm -o -path /var/lib/dnf -o -path /usr/lib/sysimage/rpm -o -path /usr/lib/sysimage/libdnf5 -o -path /var/lib/pacman \
  -o -path /etc/ld.so.cache -o -path /usr/share/applications/mimeinfo.cache -o -path /usr/share/mime \
  -o -path /usr/share/icons/hicolor/icon-theme.cache -o -path /root/.cache -o -path /etc/alternatives/.placeholder \) -prune -o -print 2>/dev/null | sort'

for image in "${IMAGES[@]}"; do
  slug="${image//[:\/]/-}"
  log="$RESULTS/$slug.log"
  echo "==> $image"
  case "$image" in
    fedora*|rocky*|alma*|opensuse*) kind=rpm ;;
    arch*) kind=pacman ;;
    *) kind=deb ;;
  esac

  name="wittymediaclient-inst-$slug"
  docker rm -f "$name" >/dev/null 2>&1
  # Privileged so that the app's sandbox has what it needs: it's on in every run here.
  docker run -d --init --name "$name" --privileged -v "$PKGS:/pkgs" -v "$HERE:/test:ro" -v "$NODE:/usr/local/bin/test-node:ro" "$image" sleep infinity >"$log" 2>&1

  docker exec -i -e KIND="$kind" -e SNAPSHOT="$SNAPSHOT" -e SLUG="$slug" "$name" bash -s >>"$log" 2>&1 <<'SCRIPT'
set -u
fail() { echo "FAIL: $*"; exit 1; }
say() { echo; echo "##### $*"; }
APP=wittymediaclient
ROOT=/opt/WittyMediaClient
pkg=$(ls /pkgs/$APP-*-linux-amd64.$KIND)
new=$(ls /pkgs/upgrade/$APP-*-linux-amd64.$KIND)
if [ "$KIND" = deb ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update >/dev/null 2>&1
  install_pkg() { apt-get install -y --no-install-recommends "$@" >/tmp/out 2>&1 || { tail -n 30 /tmp/out; fail "installing $*"; }; }
  remove_pkg() { apt-get remove -y $APP >/tmp/out 2>&1 || { cat /tmp/out; fail removing; }; }
  purge_pkg() { apt-get purge -y $APP >/tmp/out 2>&1 || { cat /tmp/out; fail purging; }; }
  is_installed() { dpkg-query -W -f='${Status}' $APP 2>/dev/null | grep -q 'install ok installed'; }
  version() { dpkg-query -W -f='${Version}' $APP; }
  test_tools="xvfb xauth procps"
elif [ "$KIND" = pacman ]; then
  pacman -Sy --noconfirm >/dev/null 2>&1
  install_pkg() {
    case "$1" in
      *.pacman) pacman -U --noconfirm "$@" >/tmp/out 2>&1 ;;
      *) pacman -S --noconfirm --needed "$@" >/tmp/out 2>&1 ;;
    esac || { tail -n 30 /tmp/out; fail "installing $*"; }
  }
  remove_pkg() { pacman -R --noconfirm $APP >/tmp/out 2>&1 || { cat /tmp/out; fail removing; }; }
  purge_pkg() { :; }
  is_installed() { pacman -Q $APP >/dev/null 2>&1; }
  version() { pacman -Q $APP | cut -d' ' -f2; }
  test_tools="xorg-server-xvfb xorg-xauth procps-ng which diffutils"
else
  install_pkg() { dnf install -y "$@" >/tmp/out 2>&1 || { tail -n 30 /tmp/out; fail "installing $*"; }; }
  remove_pkg() { dnf remove -y --setopt=clean_requirements_on_remove=False $APP >/tmp/out 2>&1 || { cat /tmp/out; fail removing; }; }
  purge_pkg() { :; }
  is_installed() { rpm -q $APP >/dev/null 2>&1; }
  version() { rpm -q --qf '%{VERSION}' $APP; }
  test_tools="xorg-x11-server-Xvfb xorg-x11-xauth procps-ng shadow-utils util-linux findutils diffutils"
fi

check_outside() { # nothing from the app's data folder or its network log says it reached anything else
  bdic=$(find /home/tester/.config -name '*.bdic' 2>/dev/null)
  [ -z "$bdic" ] || { ls -la $bdic; grep -oE 'https?://[a-zA-Z0-9.-]+' /tmp/net.json | sort -u; fail "it fetched a spelling dictionary from outside"; }
  [ -s /tmp/net.json ] || fail "no network log to read"
  hosts=$(grep -oE 'https?://[a-zA-Z0-9.-]+' /tmp/net.json | sort -u | grep -vE '://(127\.|localhost|10\.|172\.|192\.168\.|a-made-up-server)' || true)
  [ -z "$hosts" ] || { echo "$hosts"; fail "it reached outside addresses"; }
  echo "reached nothing outside: $(grep -oE 'https?://[a-zA-Z0-9.-]+' /tmp/net.json | sort -u | wc -l) local addresses in its network log"
}
open_app() { # where the screenshot goes
  rm -f /tmp/app.log /tmp/net.json
  su tester -c "cd ~ && exec xvfb-run -a $APP --remote-debugging-port=9333 --remote-allow-origins='*' --log-net-log=/tmp/net.json" >/tmp/app.log 2>&1 &
  appshell=$!
  test-node /test/app-smoke.mjs 9333 "$1" || { tail -n 30 /tmp/app.log; fail "the app didn't open"; }
  grep -q 'no-sandbox\|setuid sandbox' /tmp/app.log && { cat /tmp/app.log; fail "the sandbox complained"; }
  # Each of its processes must have its sandbox on: the app wasn't told otherwise.
  ps -eo args | grep -- "--type=renderer" | grep -v grep | grep -q -- --no-sandbox && fail "renderers run without the sandbox"
  # Asked to quit properly, or the network log isn't finished. It's a failure if it won't.
  test-node /test/app-close.mjs 9333 || fail "couldn't ask it to quit"
  for _ in $(seq 1 30); do pgrep -f "$APP" >/dev/null || break; sleep 1; done
  pgrep -f "$APP" >/dev/null && { ps -eo args | grep "$APP" | cut -c1-120; fail "it didn't quit when asked"; }
  wait "$appshell" 2>/dev/null
  pkill Xvfb 2>/dev/null
  sleep 1
  check_outside
}

say "from a bare system: install with only what the package declares: $pkg"
install_pkg "$pkg"
is_installed || fail "not installed"
echo "version: $(version)"
command -v $APP || fail "no command"
readlink -f "$(command -v $APP)"
[ "$(readlink -f "$(command -v $APP)")" = "$ROOT/$APP" ] || fail "the command doesn't reach the program"

say "every shared library resolves"
for f in "$ROOT/$APP" "$ROOT"/*.so "$ROOT"/*.so.* "$ROOT/chrome_crashpad_handler"; do
  [ -f "$f" ] || continue
  missing=$(ldd "$f" 2>&1 | grep 'not found')
  [ -z "$missing" ] || { echo "$f:"; echo "$missing"; fail "a library is missing"; }
done
echo "none missing, in $(ls "$ROOT"/*.so* "$ROOT/$APP" | wc -l) programs and libraries"

say "nothing it installs is writable by everyone"
bad=$(find "$ROOT" /usr/share/applications/$APP.desktop /usr/share/icons/hicolor/*/apps/$APP.png -perm /o+w ! -type l)
[ -z "$bad" ] || { echo "$bad"; fail "world-writable files"; }
stat -c '%a %n' "$ROOT/$APP" "$ROOT/chrome-sandbox" "$ROOT/resources/app.asar"

say "the menu entry"
cat /usr/share/applications/$APP.desktop
grep -q "^Exec=.*$APP" /usr/share/applications/$APP.desktop || fail "the menu entry doesn't start it"

say "it really opens, as an ordinary person, on a virtual screen"
install_pkg $test_tools
useradd -m tester
open_app "/pkgs/results/$SLUG.png"
echo "--- what it wrote in the home folder"
(cd /home/tester && find . -maxdepth 2 | sort)
[ -d /home/tester/.config/WittyMediaClient ] || fail "the data folder isn't where it should be"

say "the documented command removes what's in the home folder"
su tester -c 'rm -rf ~/.config/WittyMediaClient ~/.config/WittyMedia'
# What's left may only be what a new account starts with, and what the system's shared libraries keep for every program.
left=$(cd /home/tester && find . -mindepth 1 | grep -vE '^\./\.(bash|profile|config$|mozilla)|^\./\.cache($|/dconf|/fontconfig|/mesa_shader_cache)|^\./\.local($|/share$|/share/pki)|^\./\.config/pulse|^\./\.pki|^\./books')
[ -z "$left" ] || { echo "$left"; fail "the documented command left something of the app's"; }
(cd /home/tester && find . -maxdepth 3 -mindepth 1 | grep -v mesa_shader_cache_db/ | sort)

say "clearing it away, to leave a system with only the libraries it needs"
remove_pkg; purge_pkg
is_installed && fail "still installed"
[ ! -e "/usr/bin/$APP" ] || fail "the command stayed"
rm -rf /home/tester/.cache /home/tester/.pki /home/tester/.local /home/tester/.config/pulse

say "snapshot before"
eval "$SNAPSHOT" > /tmp/before.txt
wc -l /tmp/before.txt

say "install: $pkg"
install_pkg "$pkg"
mkdir -p /home/tester/.config/WittyMediaClient /home/tester/.config/WittyMedia
echo '{"server":"http://a-made-up-server:9797"}' > /home/tester/.config/WittyMediaClient/state.json
echo old > /home/tester/.config/WittyMedia/state.json
chown -R tester: /home/tester/.config
mkdir -p /srv/media && echo film > "/srv/media/A Made-Up Film.mkv"
echo mine > "$ROOT/my-own-file.txt"

say "upgrade: $new"
install_pkg "$new"
echo "version: $(version)"
[ "$(version | cut -d- -f1)" = 9.9.9 ] || fail "still the old version"
command -v $APP || fail "the upgrade lost the command"
[ "$(readlink -f "$(command -v $APP)")" = "$ROOT/$APP" ] || fail "the upgrade broke the command"
[ -f /home/tester/.config/WittyMediaClient/state.json ] || fail "the upgrade lost the settings"
[ -f "$ROOT/my-own-file.txt" ] || fail "the upgrade took a file it didn't make"
open_app ""
grep -q a-made-up-server /home/tester/.config/WittyMediaClient/state.json || fail "the app lost the settings on upgrade"

say "remove"
remove_pkg
tail -n 20 /tmp/out | grep -A3 'has been removed' || fail "doesn't say what's left in the home folder"
[ ! -e "$ROOT/$APP" ] || fail "the program stayed"
[ ! -e "/usr/bin/$APP" ] || fail "the command stayed"
[ ! -e "/usr/share/applications/$APP.desktop" ] || fail "the menu entry stayed"
[ -f "$ROOT/my-own-file.txt" ] || fail "took a file it didn't make"
[ -f /home/tester/.config/WittyMediaClient/state.json ] || fail "removing took the settings"
[ -f "/srv/media/A Made-Up Film.mkv" ] || fail "A FILM WAS DELETED"
rm -f "$ROOT/my-own-file.txt"

say "purge, where there is such a thing"
purge_pkg
tail -n 3 /tmp/out
rmdir "$ROOT" 2>/dev/null

say "the documented command, then the snapshot after"
su tester -c 'rm -rf ~/.config/WittyMediaClient ~/.config/WittyMedia'
rm -rf /home/tester/.cache /home/tester/.pki /home/tester/.local /home/tester/.config/pulse /srv/media
eval "$SNAPSHOT" > /tmp/after.txt
if ! diff -u /tmp/before.txt /tmp/after.txt > /tmp/diff.txt; then
  cat /tmp/diff.txt
  fail "something was left behind or changed"
fi
echo "NOTHING LEFT: $(wc -l < /tmp/after.txt) paths before and after are the same"

appimage=$(ls /pkgs/$APP-*-linux-amd64.AppImage 2>/dev/null)
if [ -n "$appimage" ]; then
  say "the AppImage opens too: $appimage"
  cp "$appimage" /tmp/$APP.AppImage && chmod 755 /tmp/$APP.AppImage
  # Without FUSE in the container, it unpacks itself to run.
  su tester -c "cd ~ && APPIMAGE_EXTRACT_AND_RUN=1 exec xvfb-run -a /tmp/$APP.AppImage --remote-debugging-port=9333 --remote-allow-origins='*'" >/tmp/app.log 2>&1 &
  appshell=$!
  test-node /test/app-smoke.mjs 9333 "" || { tail -n 30 /tmp/app.log; fail "the AppImage didn't open"; }
  test-node /test/app-close.mjs 9333
  wait "$appshell" 2>/dev/null
  pkill Xvfb 2>/dev/null
  su tester -c 'rm -rf ~/.config/WittyMediaClient ~/.config/WittyMedia'
fi
echo ALLPASSED
SCRIPT
  if tail -n 1 "$log" | grep -q ALLPASSED; then
    echo "   passed: $log"
  else
    echo "   FAILED: $log"
    tail -n 25 "$log"
    FAILED=1
  fi
  docker rm -f "$name" >/dev/null 2>&1
done
exit $FAILED
