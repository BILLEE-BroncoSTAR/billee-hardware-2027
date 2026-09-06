#!/usr/bin/env bash
# Runs Spectral Analysis on a virtual display (the Jetson is headless) and
# shares that display over VNC, so it can be viewed/controlled from another
# machine on the same network with any VNC viewer.
#
# One-time setup: run ./jetson_install_me.sh  (installs xvfb x11vnc fluxbox
# blueman dbus-x11 flatpak + Flatpak Chromium, and caches the app offline).
set -euo pipefail

RESOLUTION="640x480x24"
WINDOW_SIZE="640,430"
VNC_PORT="5900"
APP_URL="https://spectralanalysis.app/"  # must match launch-spectral-analysis.sh
FLATPAK_APP="org.chromium.Chromium"      # must match launch-spectral-analysis.sh
VNC_PASSWD_FILE="${HOME}/.vnc/spectral-analysis.passwd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for bin in Xvfb x11vnc fluxbox setsid; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "Missing '$bin' — run ./jetson_install_me.sh first." >&2
    exit 1
  }
done

# Bluetooth GUI is optional: if blueman isn't installed the spectrometer kiosk
# still runs. Run jetson_install_me.sh to add it.
BT_WIDGET=0
if command -v blueman-applet >/dev/null 2>&1; then
  BT_WIDGET=1
else
  echo "Note: blueman not found — skipping the Bluetooth GUI." >&2
fi

LAUNCH_SCRIPT="$SCRIPT_DIR/launch-spectral-analysis.sh"
[ -f "$LAUNCH_SCRIPT" ] || {
  echo "Error: $LAUNCH_SCRIPT not found next to this script." >&2
  exit 1
}

# A previous kiosk run that was killed hard (SSH drop, `screen` dying, SIGKILL)
# leaves orphans behind: an x11vnc still bound to our port, a stray Xvfb,
# fluxbox, blueman, the flatpak browser. The next run's x11vnc then can't bind
# 5900 and the whole session collapses. Clear our own leftovers first — this is
# a single-purpose appliance, nothing else here uses these.
reap_orphans() {
  local uid; uid="$(id -u)"
  pkill -u "$uid" -f -- "--app=${APP_URL}" 2>/dev/null || true
  command -v flatpak >/dev/null 2>&1 && flatpak kill "$FLATPAK_APP" 2>/dev/null || true
  pkill -u "$uid" -x blueman-applet 2>/dev/null || true
  pkill -u "$uid" -x blueman-manager 2>/dev/null || true
  pkill -u "$uid" -f "x11vnc .*-rfbport ${VNC_PORT} " 2>/dev/null || true
  pkill -u "$uid" -x fluxbox 2>/dev/null || true
  pkill -u "$uid" -x Xvfb 2>/dev/null || true
  sleep 1
}
echo "Clearing any leftovers from a previous run..."
reap_orphans

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

_cleaned=0
cleanup() {
  if [ "$_cleaned" = 1 ]; then return 0; fi
  _cleaned=1
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
  # The flatpak'd browser may be reparented away from us; make sure it's gone.
  pkill -f -- "--app=${APP_URL}" 2>/dev/null || true
  command -v flatpak >/dev/null 2>&1 && flatpak kill "$FLATPAK_APP" 2>/dev/null || true

  echo "Tearing down virtual display and VNC..."
  kill "${X11VNC_PID:-}" "${BLUEMAN_PID:-}" "${BLUEMAN_MGR_PID:-}" \
    "${FLUXBOX_PID:-}" "${XVFB_PID:-}" 2>/dev/null || true
  [ -n "${PRIVATE_DBUS_PID:-}" ] && kill "$PRIVATE_DBUS_PID" 2>/dev/null || true
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM
trap 'cleanup; exit 129' HUP

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

# blueman needs a D-Bus *session* bus. Prefer the real per-user bus (present
# when `loginctl enable-linger` has been run — jetson_install_me.sh does that),
# since that's also where systemd --user lives. Otherwise fall back to a
# private bus for this run, torn down in cleanup().
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -S "${XDG_RUNTIME_DIR}/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
  echo "Using the per-user D-Bus session bus (${XDG_RUNTIME_DIR}/bus)."
elif [ "$BT_WIDGET" = 1 ] && command -v dbus-launch >/dev/null 2>&1; then
  if dbus_env="$(dbus-launch --sh-syntax)"; then
    eval "$dbus_env"
    export DBUS_SESSION_BUS_ADDRESS
    PRIVATE_DBUS_PID="${DBUS_SESSION_BUS_PID:-}"
    echo "Started a private D-Bus session bus (pid ${PRIVATE_DBUS_PID:-?})."
    echo "Tip: 'sudo loginctl enable-linger \$USER' gives a persistent one." >&2
  else
    echo "Warning: no session bus available — Bluetooth GUI may misbehave." >&2
  fi
fi

setsid fluxbox &
FLUXBOX_PID=$!

VNC_LOG="${HOME}/.vnc/spectral-analysis.log"
setsid x11vnc -display "$DISPLAY_NUM" -forever -shared -rfbport "$VNC_PORT" \
  -rfbauth "$VNC_PASSWD_FILE" -o "$VNC_LOG" &
X11VNC_PID=$!

# Make sure x11vnc actually came up (bound the port, didn't crash on an X
# extension) before telling the user it's ready.
sleep 2
if ! kill -0 "$X11VNC_PID" 2>/dev/null; then
  echo "x11vnc failed to start. Last lines of ${VNC_LOG}:" >&2
  tail -n 15 "$VNC_LOG" 2>/dev/null | sed 's/^/  /' >&2
  echo "If it says the port is in use, a stray x11vnc survived — 'pkill -x x11vnc' and retry." >&2
  exit 1
fi

echo "VNC ready on port ${VNC_PORT}."
echo "From another machine on the same network, connect a VNC viewer to: $(hostname -I | awk '{print $1}'):${VNC_PORT}"

# Bluetooth GUI: the applet docks in the fluxbox toolbar tray (adapter toggle,
# notifications); the manager is the full "Bluetooth Devices" window for
# scanning / pairing / removing. Both, so nothing has to be hunted for on a
# 640x480 VNC. fluxbox needs a moment to bring its tray up first.
if [ "$BT_WIDGET" = 1 ]; then
  sleep 1
  setsid blueman-applet >/dev/null 2>&1 &
  BLUEMAN_PID=$!
  if command -v blueman-manager >/dev/null 2>&1; then
    setsid blueman-manager >/dev/null 2>&1 &
    BLUEMAN_MGR_PID=$!
  fi
  echo "Bluetooth GUI started (tray applet + Bluetooth Devices window)."
fi

# Is the spectrometer browser (the process carrying our --app= URL) running?
browser_running() { pgrep -f -- "--app=${APP_URL}" >/dev/null 2>&1; }

# Start the browser and wait up to ~15s for it to actually appear. Records the
# main pid in CHROME_PID for cleanup()'s graceful close.
launch_browser() {
  echo "Launching the spectrometer..."
  setsid bash "$LAUNCH_SCRIPT" &
  for _ in $(seq 1 30); do
    if browser_running; then
      CHROME_PID="$(pgrep -f -- "--app=${APP_URL}" | head -1 || true)"
      echo "Spectrometer window is up (pid ${CHROME_PID:-?})."
      return 0
    fi
    sleep 0.5
  done
  return 1
}

CHROME_PID=""
browser_warned=0
browser_retried=0
launch_browser || true

echo
echo "Kiosk is running. Press Ctrl-C here to stop everything."

# Supervise until Ctrl-C. The session (VNC + Bluetooth GUI) stays up even if
# the browser never starts or crashes — only Xvfb/x11vnc dying ends it.
while true; do
  sleep 5

  if ! kill -0 "${XVFB_PID:-}" 2>/dev/null; then
    echo "Xvfb died — ending the session." >&2
    exit 1
  fi
  if ! kill -0 "${X11VNC_PID:-}" 2>/dev/null; then
    echo "x11vnc died — ending the session. Last lines of ${VNC_LOG}:" >&2
    tail -n 15 "$VNC_LOG" 2>/dev/null | sed 's/^/  /' >&2
    exit 1
  fi

  if browser_running; then
    browser_warned=0
    continue
  fi

  # Browser is not up.
  if [ "$browser_retried" -eq 0 ]; then
    echo "Spectrometer browser isn't running — retrying once..." >&2
    browser_retried=1
    launch_browser || true
  elif [ "$browser_warned" -eq 0 ]; then
    browser_warned=1
    echo >&2
    echo "Spectrometer browser still won't stay up. The VNC + Bluetooth GUI" >&2
    echo "session is still running. To debug the browser, on the Jetson run:" >&2
    echo "  flatpak run ${FLATPAK_APP} --version" >&2
    echo "  flatpak run ${FLATPAK_APP} ${APP_URL}     # watch for the real error" >&2
    echo "If Web Bluetooth can't see the adapter, re-run jetson_install_me.sh" >&2
    echo "or: flatpak override --user --device=all --system-talk-name=org.bluez ${FLATPAK_APP}" >&2
  fi
done
