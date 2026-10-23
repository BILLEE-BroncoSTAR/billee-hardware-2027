import time
import odrive
from odrive.enums import ENCODER_MODE_HALL, AXIS_STATE_IDLE, AXIS_STATE_MOTOR_CALIBRATION

def find_odesc():
    return odrive.find_sync()

def calibrate_encoder(odrv0):
    odrv0.axis0.encoder.config.mode = ENCODER_MODE_HALL
    odrv0.axis0.encoder.config.cpr = 42          # NEO: 7 pole pairs x 6 Hall states
    odrv0.axis0.motor.config.pole_pairs = 7
    odrv0.axis0.motor.config.current_lim = 40

    odrv0.axis0.requested_state = AXIS_STATE_MOTOR_CALIBRATION
    while odrv0.axis0.current_state != AXIS_STATE_IDLE:
        time.sleep(0.1)
    if odrv0.axis0.motor.error != 0:
        raise RuntimeError(f"Motor calibration failed, error code {odrv0.axis0.motor.error}")

def calibrate_motor_controller(odrv0, node_id: int = None):
    if node_id is None:
        raise ValueError("Must specify a node_id!")

    odrv0.axis0.requested_state = AXIS_STATE_ENCODER_OFFSET_CALIBRATION
    while odrv0.axis0.current_state != AXIS_STATE_IDLE:
        time.sleep(0.1)

    if odrv0.axis0.encoder.error != 0:
        raise RuntimeError(f"Cannot proceed with configuration, encoder error code {odrv0.axis0.encoder.error}")

    offset = odrv0.axis0.encoder.config.phase_offset_float
    if not (-0.5 <= offset <= 0.5):
        raise RuntimeError(f"Bad Hall calibration value for phase offset: {offset}")

    # Only mark as pre-calibrated once we've confirmed it succeeded
    odrv0.axis0.motor.config.pre_calibrated = True
    odrv0.axis0.encoder.config.pre_calibrated = True

    odrv0.axis0.config.can.node_id = node_id
    odrv0.can.config.baud_rate = 500000

def save_config(odrv0):
    odrv0.save_configuration()
    odrv0.reboot()

def jog_odesc(odrv0, duration=1.0):
    odrv0.axis0.requested_state = AXIS_STATE_CLOSED_LOOP_CONTROL
    odrv0.axis0.controller.input_vel = 1     # should spin gently
    time.sleep(duration)
    odrv0.axis0.controller.input_vel = 0
    odrv0.axis0.requested_state = AXIS_STATE_IDLE
