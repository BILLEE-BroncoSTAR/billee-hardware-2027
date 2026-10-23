#!/usr/bin/env bash
# Launches Vernier Spectral Analysis as a standalone app window, acting like
# a bookmarked shortcut. Uses a dedicated Chromium profile so the installed
# PWA / service-worker cache persists between runs (needed for offline use).
set -euo pipefail

APP_URL="https://spectralanalysis.app/"
FLATPAK_APP="org.chromium.Chromium"

# flatpak (and Chromium's own profile handling) want XDG_RUNTIME_DIR; it isn't
# set under `runuser` or a bare cron/ssh context.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Pick the browser:
#   CHROMIUM_CMD=...  caller override (space-separated), wins outright
#   else Flatpak org.chromium.Chromium if installed — the supported path on the
#        Jetson; Ubuntu's "chromium-browser" is the broken snap wrapper
#   else a native chromium/chrome on PATH
browser_kind="native"
native_bin=""
if [ -n "${CHROMIUM_CMD:-}" ]; then
  browser_kind="custom"
elif command -v flatpak >/dev/null 2>&1 && \
     flatpak info "$FLATPAK_APP" >/dev/null 2>&1; then
  browser_kind="flatpak"
else
  for bin in chromium-browser chromium google-chrome-stable google-chrome; do
    if command -v "$bin" >/dev/null 2>&1; then
      native_bin="$bin"
      break
    fi
  done
  if [ -z "$native_bin" ]; then
    echo "Error: no browser found — install Flatpak Chromium with:" >&2
    echo "  flatpak install -y flathub $FLATPAK_APP" >&2
    echo "(or run jetson_install_me.sh, which does this for you)." >&2
    exit 1
  fi
fi

# Dedicated profile so the installed PWA / service-worker cache persists between
# runs. The snap build has its own AppArmor-confined area; everything else
# (including the flatpak, via an explicit --filesystem grant below) uses the
# usual ~/.config path.
if [ "$browser_kind" = native ] && command -v snap >/dev/null 2>&1 && \
   snap list chromium >/dev/null 2>&1; then
  PROFILE_DIR="${HOME}/snap/chromium/common/spectral-analysis-app"
else
  PROFILE_DIR="${HOME}/.config/spectral-analysis-app"
fi

# Build the launch command as an array (flatpak needs several words).
case "$browser_kind" in
  custom)  read -r -a chromium_cmd <<<"$CHROMIUM_CMD" ;;
  flatpak) chromium_cmd=(flatpak run "--filesystem=${PROFILE_DIR}" "$FLATPAK_APP") ;;
  native)  chromium_cmd=("$native_bin") ;;
esac

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
# of opening a real window on the current display. Kill it and *wait for it
# to actually die* before clearing the singleton files — snap Chromium can
# take several seconds to exit, and if it's still alive it just recreates
# them and the forward-and-exit happens anyway.
profile_procs() { pgrep -f -- "--user-data-dir=$PROFILE_DIR" >/dev/null 2>&1; }
if profile_procs; then
  echo "Stopping an earlier Chromium still holding this profile..." >&2
  pkill -f -- "--user-data-dir=$PROFILE_DIR" 2>/dev/null || true
  for _ in $(seq 1 20); do
    profile_procs || break
    sleep 0.5
  done
  if profile_procs; then
    pkill -9 -f -- "--user-data-dir=$PROFILE_DIR" 2>/dev/null || true
    sleep 1
  fi
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

exec "${chromium_cmd[@]}" \
  --user-data-dir="$PROFILE_DIR" \
  --app="$APP_URL" \
  --disable-gpu \
  --disable-software-rasterizer \
  --ozone-platform=x11 \
  "${window_flags[@]}" \
  "$@"
