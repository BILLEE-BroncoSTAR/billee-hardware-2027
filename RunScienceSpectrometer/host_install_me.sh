#!/usr/bin/env bash
# Run this on the x86 Linux machine you'll VIEW the Jetson from (not on the
# Jetson itself) — installs a VNC viewer so you can connect to the session
# started by start-remote-kiosk.sh on the Jetson. Usage: sudo ./host_install_me.sh
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Run this with sudo: sudo ./host_install_me.sh" >&2
  exit 1
fi

echo "Installing a VNC viewer (TigerVNC)..."
apt-get update
apt-get install -y tigervnc-viewer

echo
echo "Done. Connect to the Jetson with:"
echo "  vncviewer <jetson-ip>:5900"
echo "(the Jetson prints its IP when you run start-remote-kiosk.sh there)"
