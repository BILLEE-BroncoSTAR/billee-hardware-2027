# Vernier Spectral Analysis on Jetson Orin AGX (offline, Bluetooth)

Short setup guide for running Vernier's Spectral Analysis PWA (`https://spectralanalysis.app`)
locally on a Jetson Orin AGX (L4T / Ubuntu, arm64), fully offline, talking to a
Go Direct spectrometer over Bluetooth LE.

This does **not** copy or repackage Vernier's app. It relies on the app's own
built-in PWA offline support (service worker + Web Bluetooth), which Vernier
documents as the intended way to run it without a network connection.

## Prerequisites

- Jetson Orin AGX running L4T Ubuntu (20.04/22.04-based)
- Internet access for the *one-time* first run only
- A Vernier Go Direct spectrometer, charged and powered on

## Quick setup

Do steps 1-3 below in one shot:

```bash
sudo ./jetson_install_me.sh
```

Installs Flatpak Chromium + BlueZ/blueman/Xvfb/x11vnc/fluxbox/flatpak, wires
up Bluetooth GUI permissions, opens the app once on a throwaway virtual
display to let its service worker cache everything, then closes and tells you
it's ready to run offline. Needs internet for that one run only. Skip to
[step 5](#5-connect-the-spectrometer) once it's done, or read on for what it's
doing under the hood / how to do it by hand.

## 1. Install a Bluetooth-capable Chromium

Ubuntu 24.04's `chromium-browser` package is the **snap** wrapper, and snap
Chromium won't launch from the headless kiosk session (it can't get a systemd
scope). Use the **Flatpak** build instead:

```bash
sudo apt update
sudo apt install -y flatpak bluez
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub org.chromium.Chromium
sudo flatpak override --system --device=all --system-talk-name=org.bluez org.chromium.Chromium
flatpak run org.chromium.Chromium --version
```

`launch-spectral-analysis.sh` auto-detects this (`flatpak info
org.chromium.Chromium`) and uses it; set `CHROMIUM_CMD` to override.

## 2. Make sure Bluetooth is up

```bash
sudo systemctl enable --now bluetooth
bluetoothctl power on
```

Add your user to the `bluetooth` group if you hit permission errors, then
log out/in:

```bash
sudo usermod -aG bluetooth "$USER"
```

## 3. First run: cache the app while online

`jetson_install_me.sh` does this automatically. By hand:

1. `flatpak run org.chromium.Chromium https://spectralanalysis.app/` and let
   it fully load.
2. Click the install icon in the address bar (or menu → *Install Spectral
   Analysis*). This registers the service worker and precaches the app shell.
3. Close the browser.

## 4. Verify it works offline

1. Disconnect the Jetson from the network (or block it at the router).
2. Run the launcher script below.
3. Confirm the app UI loads from cache with no network.

## 5. Connect the spectrometer

In the app, use its "Connect device" control — this opens the standard Web
Bluetooth device chooser. Select the spectrometer from the list. No OS-level
pairing step is normally required; Web Bluetooth handles the GATT connection
directly.

## 6. Everyday launch

Use [`launch-spectral-analysis.sh`](launch-spectral-analysis.sh) to open the
app directly in its own window (like a desktop shortcut/bookmark), instead of
navigating there by hand each time.

## Viewing it from another machine (headless Jetson)

The app itself isn't a web server (unlike something like F Prime GDS), so
there's no port to just forward — it's a real GUI window that needs a
Bluetooth-capable browser. Since this Jetson has no monitor, use a virtual
display + VNC instead. `jetson_install_me.sh` installs everything for this
(`xvfb x11vnc fluxbox blueman dbus-x11 flatpak` + **Flatpak Chromium**,
`org.chromium.Chromium`). Ubuntu 24.04's `chromium-browser` is the snap
wrapper and snap Chromium won't launch from this headless session, so the
kiosk uses the Flatpak build instead.

```bash
./start-remote-kiosk.sh      # runs in the foreground; Ctrl-C stops it
```

First run asks you to set a VNC password, then it prints the Jetson's IP.
From another machine on the same network, connect to it with a VNC viewer at
`<jetson-ip>:5900`.

### Detached (so you can close the SSH session)

From the repo root, `make science run` starts the kiosk inside a detached
`screen` session (`billee-kiosk`) instead — it installs `screen` if missing,
prompts once for the VNC password, then leaves the kiosk running when you log
out:

```bash
make science run       # start detached
make science attach    # re-attach to watch it   (Ctrl-A then D to detach)
make science stop      # Ctrl-C the kiosk and close the screen session
```

This is a plain `screen` session, not a boot service — it does not restart the
kiosk after a reboot or a crash.

The kiosk opens two things on the virtual display:

- **Spectral Analysis** (the Flatpak Chromium `--app` window).
- **blueman** — the tray applet *and* the full "Bluetooth Devices" window, for
  scanning / pairing / removing devices and toggling the adapter with a GUI.

The session **stays up until you Ctrl-C it**, even if the browser fails to
start or the Bluetooth GUI has trouble — so you can still use one while
debugging the other. Only Xvfb or x11vnc dying ends it on its own.

For blueman to *control* the adapter (not just view it), your user must be in
the `bluetooth` group, the polkit rule at
`/etc/polkit-1/rules.d/51-blueman.rules` must be present, and `systemd --user`
must be running for a real session bus. `jetson_install_me.sh` sets up all
three (`usermod -aG bluetooth`, the polkit rule, and `loginctl enable-linger`)
— **log out and back in (or reboot) once** after that first install so the
group and linger take effect.

The viewing machine needs an **x86 Linux-compatible VNC viewer** — on that
machine (not the Jetson), run:

```bash
sudo ./host_install_me.sh
vncviewer <jetson-ip>:5900
```

Ctrl-C in the terminal running the script shuts down the virtual display,
Chromium (`flatpak kill` too), the VNC server, blueman, and any private D-Bus
session it started.

## Troubleshooting

- **Device chooser doesn't show the spectrometer** — check `bluetoothctl
  show` reports the adapter as `Powered: yes`; try `sudo systemctl restart
  bluetooth`.
- **App won't load offline** — re-run `jetson_install_me.sh` (the caching
  pass); the service worker only caches after a full successful load. Check
  `chrome://serviceworker-internals` in the app for its registration status.
- **Spectrometer window won't stay up** — the kiosk keeps the VNC/Bluetooth
  session running and prints how to debug. On the Jetson:
  ```bash
  flatpak run org.chromium.Chromium --version
  flatpak run org.chromium.Chromium https://spectralanalysis.app/   # watch stderr
  ```
- **Web Bluetooth can't see the adapter** (from the Flatpak build) — the
  sandbox needs BlueZ access:
  ```bash
  flatpak override --user --device=all \
    --system-talk-name=org.bluez org.chromium.Chromium
  ```
  `jetson_install_me.sh` does the `--system` equivalent; if Web Bluetooth
  still fails, `sudo apt install xdg-desktop-portal` and it'll be picked up.
- **blueman opens but "Not authorized" / can't toggle the adapter** — you're
  not in the `bluetooth` group yet, or linger isn't active, or
  `/etc/polkit-1/rules.d/51-blueman.rules` is missing. Log out/in after
  `jetson_install_me.sh`, or re-run it.
- **No Bluetooth GUI at all** — the kiosk prints a `Note:` at startup if
  `blueman` isn't installed. `sudo apt install blueman dbus-x11`.
- **Stale profile / singleton lock** — delete the profile dir and re-cache
  (never with `sudo`):
  ```bash
  rm -rf ~/.config/spectral-analysis-app        # or ~/snap/chromium/common/spectral-analysis-app
  ./jetson_install_me.sh
  ```
