#!/bin/bash
# Removes WittyMediaClient and everything it keeps for you on this Mac. Double-click it, or run it
# in Terminal. It lists what it found and asks before removing anything. Your servers and what's
# on them are never touched. Add --dry-run to only see the list.

APP_NAME=WittyMediaClient
OLD_NAME=WittyMedia
BUNDLE_ID=com.wittywilla.wittymediaclient
KEPT="settings, saved sign-ins, logs and caches"
NEVER="your servers or anything on them"

DRY_RUN=0
[ "$1" = "--dry-run" ] && DRY_RUN=1

LIB="$HOME/Library"
candidates=(
  "/Applications/$APP_NAME.app"
  "$HOME/Applications/$APP_NAME.app"
  "$LIB/Application Support/$APP_NAME"
  "$LIB/Application Support/$OLD_NAME"
  "$LIB/Caches/$APP_NAME"
  "$LIB/Caches/$BUNDLE_ID"
  "$LIB/Caches/$BUNDLE_ID.ShipIt"
  "$LIB/HTTPStorages/$BUNDLE_ID"
  "$LIB/HTTPStorages/$BUNDLE_ID.binarycookies"
  "$LIB/Logs/$APP_NAME"
  "$LIB/Preferences/$BUNDLE_ID.plist"
  "$LIB/Preferences/$BUNDLE_ID.helper.plist"
  "$LIB/Saved Application State/$BUNDLE_ID.savedState"
  "$LIB/WebKit/$BUNDLE_ID"
)

found=()
for path in "${candidates[@]}"; do
  if [ -e "$path" ]; then found+=("$path"); fi
done

if [ ${#found[@]} -eq 0 ]; then
  echo "$APP_NAME isn't on this Mac for your account: there is nothing to remove."
  exit 0
fi

echo "This removes $APP_NAME and your $KEPT:"
echo
for path in "${found[@]}"; do echo "  $path"; done
echo
echo "Nothing else on this Mac is touched, including $NEVER."
echo "Other accounts on this Mac keep what they have in their own Library folders."
echo

if [ "$DRY_RUN" = 1 ]; then
  echo "Dry run: nothing was removed."
  exit 0
fi

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "$APP_NAME is open. Quit it, then run this again."
  exit 1
fi

printf 'Remove all of this? Type yes to go ahead: '
read -r answer
if [ "$answer" != "yes" ]; then
  echo "Nothing was removed."
  exit 0
fi

failed=0
for path in "${found[@]}"; do
  if rm -rf -- "$path" 2>/dev/null && [ ! -e "$path" ]; then
    echo "Removed $path"
  elif [ "${path#/Applications/}" != "$path" ]; then
    echo "Removing $path needs an administrator's password."
    if sudo rm -rf -- "$path"; then echo "Removed $path"; else echo "Couldn't remove $path"; failed=1; fi
  else
    echo "Couldn't remove $path"
    failed=1
  fi
done

# The system keeps its own copy of the preferences for a while unless it's told.
if command -v defaults >/dev/null 2>&1; then
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1
fi

echo
if [ "$failed" = 0 ]; then
  echo "$APP_NAME is gone. You can close this window."
else
  echo "Some items couldn't be removed: they are listed above."
  exit 1
fi
