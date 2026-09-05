#!/usr/bin/env bash
# One-time setup: installs everything needed, opens Spectral Analysis once
# so its service worker fully caches the app for offline use, then exits.
# Needs internet only for this one run. Usage: sudo ./install-me.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
LAUNCH_SCRIPT="$SCRIPT_DIR/launch-spectral-analysis.sh"

cache_app() {
  [ -f "$LAUNCH_SCRIPT" ] || {
    echo "Error: $LAUNCH_SCRIPT not found next to this script." >&2
    exit 1
  }
  for bin in Xvfb curl setsid; do
    command -v "$bin" >/dev/null 2>&1 || {
      echo "Missing '$bin' — the install step above didn't complete correctly." >&2
      exit 1
    }
  done

  local debug_port=9223
  local pipe
  pipe="$(mktemp -u)"
  mkfifo -m 600 "$pipe"
  exec {DISPLAYFD}<>"$pipe"
  rm -f "$pipe"

  setsid Xvfb -displayfd "$DISPLAYFD" -screen 0 1600x900x24 &
  local xvfb_pid=$!
  if ! read -r -u "$DISPLAYFD" -t 10 display_num; then
    echo "Error: Xvfb didn't start correctly." >&2
    kill "$xvfb_pid" 2>/dev/null || true
    exit 1
  fi
  exec {DISPLAYFD}<&-
  export DISPLAY=":${display_num}"

  setsid bash "$LAUNCH_SCRIPT" "--remote-debugging-port=${debug_port}" &
  local chrome_pid=$!

  cleanup() {
    kill -TERM "$chrome_pid" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$chrome_pid" 2>/dev/null || break
      sleep 0.5
    done
    kill -KILL "$chrome_pid" 2>/dev/null || true
    kill "$xvfb_pid" 2>/dev/null || true
  }
  trap cleanup EXIT

  echo "Loading the app (needs internet this one time)..."
  local loaded=false
  for _ in $(seq 1 30); do
    if curl -s "http://localhost:${debug_port}/json" 2>/dev/null | grep -q "spectralanalysis.app"; then
      loaded=true
      break
    fi
    sleep 1
  done
  if [ "$loaded" != true ]; then
    echo "Warning: couldn't confirm the page loaded in time, continuing anyway..." >&2
  fi

  echo "Letting the service worker finish caching everything for offline use..."
  sleep 15
}

# Root pass: install packages, then re-run this same script as the real user
# so the cached browser profile ends up in *their* home directory, not
# root's (Chromium also refuses to run as root without disabling its
# sandbox, which we don't want to do here).
if [ "$EUID" -eq 0 ]; then
  if [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = "root" ]; then
    echo "Run this as: sudo ./install-me.sh   (from your normal user account, not logged in as root)" >&2
    exit 1
  fi

  echo "Installing required packages..."
  apt-get update
  apt-get install -y chromium-browser bluez xvfb x11vnc fluxbox util-linux curl

  systemctl enable --now bluetooth

  echo "Caching the app as ${SUDO_USER}..."
  exec runuser -u "$SUDO_USER" -- "$SCRIPT_PATH" --cache-only
fi

# User pass (either invoked directly by root above, or manually re-run).
if [ "${1:-}" = "--cache-only" ]; then
  cache_app
  echo
  echo "Done — Spectral Analysis is cached and can now run fully offline."
  echo "Launch it any time with:      ./launch-spectral-analysis.sh"
  echo "Or for remote/VNC access:     ./start-remote-kiosk.sh"
  exit 0
fi

echo "Run this with: sudo ./install-me.sh" >&2
exit 1
