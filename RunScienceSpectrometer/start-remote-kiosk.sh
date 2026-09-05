#!/usr/bin/env bash
# Runs Spectral Analysis on a virtual display (the Jetson is headless) and
# shares that display over VNC, so it can be viewed/controlled from another
# machine on the same network with any VNC viewer.
#
# One-time install: sudo apt install -y xvfb x11vnc fluxbox blueman dbus-x11
set -euo pipefail

RESOLUTION="640x480x24"
WINDOW_SIZE="640,430"
VNC_PORT="5900"
VNC_PASSWD_FILE="${HOME}/.vnc/spectral-analysis.passwd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for bin in Xvfb x11vnc fluxbox setsid; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "Missing '$bin'. Install with: sudo apt install -y xvfb x11vnc fluxbox util-linux" >&2
    exit 1
  }
done

# Optional: the Bluetooth tray widget. Missing pieces just disable it — the
# spectrometer kiosk still works without them. Run jetson_install_me.sh to add.
BT_WIDGET=1
for bin in blueman-applet dbus-launch; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "Note: '$bin' not found — skipping the Bluetooth widget." >&2
    BT_WIDGET=0
  }
done

LAUNCH_SCRIPT="$SCRIPT_DIR/launch-spectral-analysis.sh"
[ -f "$LAUNCH_SCRIPT" ] || {
  echo "Error: $LAUNCH_SCRIPT not found next to this script." >&2
  exit 1
}

mkdir -p "$(dirname "$VNC_PASSWD_FILE")"
if [ ! -f "$VNC_PASSWD_FILE" ]; then
  echo "No VNC password set yet — choose one now (first-time setup only):"
  x11vnc -storepasswd "$VNC_PASSWD_FILE"
fi

# Chromium needs to fully exit (its own graceful shutdown, plus any
# "leave site?" prompt) before Xvfb/x11vnc get torn down under it, or the
# next launch can start from a bad state. Give it a bounded window to close
# itself, then force it if it doesn't.
wait_for_exit() {
  local pid="$1" timeout="$2"
  for ((i = 0; i < timeout * 2; i++)); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.5
  done
  return 1
}

cleanup() {
  echo "Shutting down..."

  if [ -n "${CHROME_PID:-}" ] && kill -0 "$CHROME_PID" 2>/dev/null; then
    echo "Asking Chromium to close..."
    kill -TERM "$CHROME_PID" 2>/dev/null || true
    if ! wait_for_exit "$CHROME_PID" 10; then
      echo "Chromium didn't exit in time, forcing it closed..." >&2
      kill -KILL "$CHROME_PID" 2>/dev/null || true
      wait_for_exit "$CHROME_PID" 5 || true
    fi
  fi

  echo "Tearing down virtual display and VNC..."
  kill "${X11VNC_PID:-}" "${BLUEMAN_PID:-}" "${FLUXBOX_PID:-}" "${XVFB_PID:-}" 2>/dev/null || true
  [ -n "${DBUS_SESSION_BUS_PID:-}" ] && kill "$DBUS_SESSION_BUS_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Each child runs in its own session (setsid) so Ctrl-C at the terminal only
# signals this script, not Chromium/Xvfb/x11vnc directly — cleanup() above
# controls the shutdown order instead of the terminal racing it.
#
# Let Xvfb pick its own free display number (-displayfd) instead of a fixed
# ":1" — a leftover Xvfb from a previous crashed/killed run can otherwise
# still be holding that number and the new one refuses to start.
DISPLAYFD_PIPE="$(mktemp -u)"
mkfifo -m 600 "$DISPLAYFD_PIPE"
exec {DISPLAYFD}<>"$DISPLAYFD_PIPE"
rm -f "$DISPLAYFD_PIPE"

setsid Xvfb -displayfd "$DISPLAYFD" -screen 0 "$RESOLUTION" &
XVFB_PID=$!

if ! read -r -u "$DISPLAYFD" -t 10 DISPLAY_NUM_RAW; then
  echo "Xvfb didn't report a display number in time — check it started correctly." >&2
  exit 1
fi
exec {DISPLAYFD}<&-
DISPLAY_NUM=":${DISPLAY_NUM_RAW}"
export DISPLAY="$DISPLAY_NUM"
export WINDOW_SIZE
echo "Using X display ${DISPLAY_NUM}"

# blueman-applet (the Bluetooth tray widget) needs a D-Bus *session* bus, which
# a bare Xvfb + fluxbox session doesn't have. Start one scoped to this run and
# tear it down in cleanup(). Also silences a batch of Chromium/GTK D-Bus noise.
if [ "$BT_WIDGET" = 1 ]; then
  if dbus_env="$(dbus-launch --sh-syntax)"; then
    eval "$dbus_env"
    export DBUS_SESSION_BUS_ADDRESS
    echo "D-Bus session bus up (pid ${DBUS_SESSION_BUS_PID:-?})"
  else
    echo "Warning: dbus-launch failed — disabling the Bluetooth widget." >&2
    BT_WIDGET=0
  fi
fi

setsid fluxbox &
FLUXBOX_PID=$!

setsid x11vnc -display "$DISPLAY_NUM" -forever -shared -rfbport "$VNC_PORT" \
  -rfbauth "$VNC_PASSWD_FILE" -o "${HOME}/.vnc/spectral-analysis.log" &
X11VNC_PID=$!

echo "VNC ready on port ${VNC_PORT}."
echo "From another machine on the same network, connect a VNC viewer to: $(hostname -I | awk '{print $1}'):${VNC_PORT}"

# Bluetooth tray widget — docks into the fluxbox toolbar's system tray (the
# strip along the bottom). Click it to scan / pair / connect / toggle the
# adapter. fluxbox needs a moment to bring its tray up first so the icon docks.
if [ "$BT_WIDGET" = 1 ]; then
  sleep 1
  setsid blueman-applet >/dev/null 2>&1 &
  BLUEMAN_PID=$!
  echo "Bluetooth widget started — look for its icon in the toolbar tray."
fi

setsid bash "$LAUNCH_SCRIPT" &
CHROME_PID=$!
chrome_started_at=$SECONDS
wait "$CHROME_PID" || true

# A near-instant exit almost always means Chromium forwarded its URL to an
# orphaned instance still holding the profile (from a killed run or a crashed
# install pass) and quit, rather than opening a window here.
if (( SECONDS - chrome_started_at < 5 )); then
  echo >&2
  echo "Chromium exited immediately — most likely an orphaned Chromium is still" >&2
  echo "holding the profile. Clear it and retry:" >&2
  echo "  pkill -9 -f spectral-analysis-app; pkill -x Xvfb" >&2
  echo "  rm -f ~/snap/chromium/common/spectral-analysis-app/Singleton{Lock,Socket,Cookie}" >&2
fi
