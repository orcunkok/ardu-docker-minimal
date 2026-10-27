"""Minimal SITL smoke test. copter: connect -> arm -> takeoff -> land -> disarmed.
plane/rover/sub (VEHICLE env): connect -> arm -> disarm."""
import os
import sys
import time

from pymavlink import mavutil

URL = os.environ.get("MAV_URL", "tcp:127.0.0.1:5760")
VEHICLE = os.environ.get("VEHICLE", "copter")
MODE = {"copter": "GUIDED", "plane": "GUIDED"}.get(VEHICLE, "MANUAL")
ALT = float(os.environ.get("TAKEOFF_ALT", "10"))


def step(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def fail(msg):
    step(f"FAIL: {msg}")
    sys.exit(1)


def connect(url, timeout=60):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            m = mavutil.mavlink_connection(url, source_system=255)
            if m.wait_heartbeat(timeout=10):
                return m
        except OSError:
            pass
        time.sleep(1)
    fail(f"no heartbeat from {url}")


def command(m, cmd, *params):
    p = list(params) + [0] * (7 - len(params))
    m.mav.command_long_send(m.target_system, m.target_component, cmd, 0, *p)
    deadline = time.time() + 5
    while time.time() < deadline:
        ack = m.recv_match(type="COMMAND_ACK", blocking=True, timeout=1)
        if ack is not None and ack.command == cmd:
            if ack.result:
                step(f"  {cmd} -> result {ack.result}")
            return ack.result == mavutil.mavlink.MAV_RESULT_ACCEPTED
    return False


def wait_until(m, pred, msg_type, timeout, what):
    deadline = time.time() + timeout
    while time.time() < deadline:
        msg = m.recv_match(type=msg_type, blocking=True, timeout=1)
        if msg is not None and pred(msg):
            return msg
    fail(f"timeout waiting for {what}")


m = connect(URL)
step(f"heartbeat from sys {m.target_system} comp {m.target_component}")
m.mav.request_data_stream_send(m.target_system, m.target_component,
                               mavutil.mavlink.MAV_DATA_STREAM_ALL, 4, 1)



def ensure_guided():
    m.set_mode(MODE)
    wait_until(m, lambda h: mavutil.mode_string_v10(h) == MODE, "HEARTBEAT", 10, MODE)


def drain_statustext():
    while (t := m.recv_match(type="STATUSTEXT", blocking=False)) is not None:
        step(f"  vehicle: {t.text}")


# Arming is refused until EKF/GPS settle, and the RC mode switch can reset the
# mode during boot, so re-assert GUIDED before every attempt.
deadline = time.time() + 120
while True:
    ensure_guided()
    if command(m, mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM, 1):
        break
    if time.time() > deadline:
        fail("could not arm")
    drain_statustext()
    time.sleep(2)
step(f"armed in {MODE}")

if VEHICLE != "copter":  # light test: just disarm again
    time.sleep(2)
    if not command(m, mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM, 0, 21196):
        fail("could not disarm")
    wait_until(m, lambda h: not h.base_mode & mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED,
               "HEARTBEAT", 10, "disarm")
    step("disarmed")
    step("PASS")
    sys.exit(0)

if not command(m, mavutil.mavlink.MAV_CMD_NAV_TAKEOFF, 0, 0, 0, 0, 0, 0, ALT):
    drain_statustext()
    fail("takeoff rejected")
pos = wait_until(m, lambda p: p.relative_alt >= (ALT - 1) * 1000,
                 "GLOBAL_POSITION_INT", 60, f"altitude {ALT - 1} m")
step(f"reached {pos.relative_alt / 1000:.1f} m")

m.set_mode("LAND")
wait_until(m, lambda h: not h.base_mode & mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED,
           "HEARTBEAT", 90, "landing and disarm")
step("landed and disarmed")
step("PASS")
