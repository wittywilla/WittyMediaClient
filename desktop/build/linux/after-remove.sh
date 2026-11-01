#!/bin/bash
# Runs after the package's files are gone, for .deb and .rpm alike. The arguments differ:
#   .deb  remove, purge, upgrade, failed-upgrade, abort-install, abort-upgrade, disappear
#   .rpm  0 when it's being removed, 1 when another version is replacing it
#   .pacman  the version being removed. It only runs this for a removal

case "$1" in
  upgrade|failed-upgrade|abort-upgrade|1) exit 0 ;; # another version is taking over
esac

if type update-alternatives >/dev/null 2>&1; then
  update-alternatives --remove '${executable}' '/opt/${sanitizedProductName}/${executable}' >/dev/null 2>&1 || true
fi
# Only ever our own link: one that points at something else belongs to someone else.
case "$(readlink '/usr/bin/${executable}' 2>/dev/null)" in
  '/opt/${sanitizedProductName}/${executable}'|'/etc/alternatives/${executable}') rm -f '/usr/bin/${executable}' ;;
esac

profile='/etc/apparmor.d/${executable}'
if [ -f "$profile" ]; then
  if apparmor_status --enabled >/dev/null 2>&1 && ! { [ -x /usr/bin/ischroot ] && /usr/bin/ischroot; } && hash apparmor_parser 2>/dev/null; then
    apparmor_parser --remove "$profile" >/dev/null 2>&1 || true
  fi
  rm -f "$profile"
fi

if hash update-mime-database 2>/dev/null; then update-mime-database /usr/share/mime >/dev/null 2>&1 || true; fi
if hash update-desktop-database 2>/dev/null; then update-desktop-database /usr/share/applications >/dev/null 2>&1 || true; fi
if hash gtk-update-icon-cache 2>/dev/null; then gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true; fi

# Folders the package manager left because nothing listed them. Never one with anything still inside.
if [ -d '/opt/${sanitizedProductName}' ]; then
  find '/opt/${sanitizedProductName}' -depth -type d -empty -delete 2>/dev/null || true
fi

case "$1" in
  remove|0|[0-9]*.*)
    echo "WittyMediaClient has been removed."
    echo "A package can't reach home folders, so your settings,"
    echo "saved sign-ins, logs and caches are still there."
    echo "To remove your own, run:"
    echo "  rm -rf ~/.config/WittyMediaClient ~/.config/WittyMedia"
    ;;
esac
exit 0
