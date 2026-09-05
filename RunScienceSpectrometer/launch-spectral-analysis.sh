#!/usr/bin/env bash
# Launches Vernier Spectral Analysis as a standalone app window, acting like
# a bookmarked shortcut. Uses a dedicated Chromium profile so the installed
# PWA / service-worker cache persists between runs (needed for offline use).
set -euo pipefail

APP_URL="https://spectralanalysis.app/"

find_chromium() {
  for bin in chromium-browser chromium google-chrome-stable google-chrome; do
    if command -v "$bin" >/dev/null 2>&1; then
      echo "$bin"
      return 0
    fi
  done
  return 1
}

CHROMIUM_BIN="$(find_chromium)" || {
  echo "Error: no Chromium/Chrome binary found on PATH." >&2
  echo "Install one with: sudo apt install chromium-browser" >&2
  exit 1
}

# The snap build of Chromium is AppArmor-confined to its own ~/snap/chromium
# tree; a --user-data-dir under ~/.config gets denied when it tries to create
# the SingletonLock symlink, no matter the file ownership. Use the snap's
# writable "common" area when the snap package is installed, otherwise fall
# back to a normal ~/.config profile for non-snap Chromium/Chrome builds.
if snap list chromium >/dev/null 2>&1; then
  PROFILE_DIR="${HOME}/snap/chromium/common/spectral-analysis-app"
else
  PROFILE_DIR="${HOME}/.config/spectral-analysis-app"
fi

if command -v bluetoothctl >/dev/null 2>&1; then
  if ! bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
    echo "Bluetooth adapter is off; attempting to power it on..." >&2
    bluetoothctl power on >/dev/null 2>&1 || \
      echo "Warning: could not power on Bluetooth automatically." >&2
  fi
fi

mkdir -p "$PROFILE_DIR"

# If a previous run (e.g. an interrupted install-me.sh caching pass) left a
# Chromium process still holding this profile, a new launch just silently
# forwards the URL to that orphaned instance and exits immediately instead
# of opening a real window on the current display. Clear it out first.
if pkill -f -- "--user-data-dir=$PROFILE_DIR" 2>/dev/null; then
  sleep 1
fi
rm -f "$PROFILE_DIR"/Singleton{Lock,Socket,Cookie}

# When a caller (start-remote-kiosk.sh) pins an explicit window size, honour it
# and place the window at the top-left so the fluxbox toolbar/menu below it stay
# reachable over VNC. Otherwise fall back to the old maximized behaviour for
# standalone desktop use.
if [ -n "${WINDOW_SIZE:-}" ]; then
  window_flags=(--window-position=0,0 --window-size="$WINDOW_SIZE")
else
  window_flags=(--start-maximized)
fi

exec "$CHROMIUM_BIN" \
  --user-data-dir="$PROFILE_DIR" \
  --app="$APP_URL" \
  --disable-gpu \
  --disable-software-rasterizer \
  --ozone-platform=x11 \
  "${window_flags[@]}" \
  "$@"
