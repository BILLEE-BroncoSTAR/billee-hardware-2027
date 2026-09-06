# ODESC Hall-Encoder Setup Script

A small script for configuring an ODESC-controlled motor (e.g. a NEO with
Hall-effect encoder) from scratch: encoder/motor calibration, CAN node
setup, saving config, and a quick jog test.

## Requirements

- Python 3
- `odrive` Python package: `pip install odrive`
- An ODESC connected over USB
- This script targets the **0.6.x** ODrive firmware/library API
  (`odrive.find_sync()`, `AXIS_STATE_*` enum names). If you're on 0.5.x,
  use `odrive.find_any()` instead, and double check enum/config paths —
  some renamed between major versions.

## What it does

| Function | Purpose |
|---|---|
| `find_odrv()` | Discovers and connects to the first ODESC found over USB. |
| `calibrate_encoder(odrv0)` | Sets Hall encoder mode, CPR, pole pairs, and current limit, then runs motor calibration. |
| `calibrate_motor_controller(odrv0, node_id)` | Runs encoder offset calibration, validates the Hall phase offset, marks the motor/encoder as pre-calibrated, and configures the CAN node ID + baud rate. |
| `save_config(odrv0)` | Saves configuration to flash and reboots the ODESC. |
| `jog_odrv(odrv0)` | Briefly spins the motor in closed-loop velocity control as a sanity check. |

## Usage


import and call the functions individually, e.g. from a REPL or
`odrivetool`:

```python
from odrive_setup import *

odrv0 = find_odrv()
calibrate_encoder(odrv0)
calibrate_motor_controller(odrv0, node_id=1)
save_config(odrv0)

odrv0 = find_odrv()   # reconnect after reboot
jog_odrv(odrv0)
```

## Important notes

- **CPR = 42** and **pole_pairs = 7** are specific to a NEO motor's 3-Hall-sensor
  setup (7 pole pairs × 6 Hall states). Change these to match your motor.
- **`current_lim = 40`** (amps) is set high for calibration/testing — lower
  this to a safe value for your motor and power supply before running on
  real hardware.
- `save_config()` reboots the ODESC. Any existing `odrv0` handle becomes
  invalid afterward — call `find_odrv()` again before further calls.
- `calibrate_motor_controller` will raise a `RuntimeError` if the Hall
  phase offset is outside the expected `[-0.5, 0.5]` range, which usually
  indicates a wiring or pole-pair mismatch. Don't ignore this and proceed
  to `save_config()`.
- `node_id` must be explicitly provided (any non-negative int, including
  `0`, is valid) — it is *not* optional despite the default of `None`.

## Known limitations

- No error handling for `find_odrv()` timing out if no ODESC is connected.
- Only configures `axis0`; extend similarly for `axis1` on dual-axis boards.
- No CLI arguments — motor parameters and `node_id` must be edited directly
  in the script or passed in via your own wrapper.
