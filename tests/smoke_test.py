"""PX4 X500 SITL smoke test.
GCS link (MAV_URL, UDP 18570): connect -> arm -> takeoff -> land -> auto-disarm.
API link (API_URL, UDP 14580, what MAVSDK/OBC software uses): heartbeat + attitude stream."""
import math
import os
import sys
import time

from pymavlink import mavutil

URL = os.environ.get("MAV_URL", "udpout:127.0.0.1:18570")
API_URL = os.environ.get("API_URL", "udpout:127.0.0.1:14580")
ALT = float(os.environ.get("TAKEOFF_ALT", "10"))
mav = mavutil.mavlink


def step(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def fail(msg):
    step(f"FAIL: {msg}")
    sys.exit(1)


def connect(url, timeout=60):
    # PX4 replies to whoever talks first, so keep sending our heartbeat until it answers.
    m = mavutil.mavlink_connection(url, source_system=255)
    deadline = time.time() + timeout
    while time.time() < deadline:
        m.mav.heartbeat_send(mav.MAV_TYPE_GCS, mav.MAV_AUTOPILOT_INVALID, 0, 0, 0)
        hb = m.recv_match(type="HEARTBEAT", blocking=True, timeout=1)
        if hb is not None and hb.get_srcComponent() == 1:
            m.target_system, m.target_component = hb.get_srcSystem(), 1
            return m
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
            return ack.result == mav.MAV_RESULT_ACCEPTED
    return False


def wait_until(m, pred, msg_type, timeout, what):
    deadline = time.time() + timeout
    while time.time() < deadline:
        msg = m.recv_match(type=msg_type, blocking=True, timeout=1)
        if msg is not None and pred(msg):
            return msg
    fail(f"timeout waiting for {what}")


def drain_statustext(m):
    while (t := m.recv_match(type="STATUSTEXT", blocking=False)) is not None:
        step(f"  vehicle: {t.text}")


def armed(h):
    return bool(h.base_mode & mav.MAV_MODE_FLAG_SAFETY_ARMED)


# --- GCS link: fly ---
m = connect(URL)
step(f"GCS link: heartbeat from sys {m.target_system} ({URL})")
home = wait_until(m, lambda p: p.lat != 0, "GLOBAL_POSITION_INT", 60, "position fix")
step(f"position {home.lat / 1e7:.6f},{home.lon / 1e7:.6f} alt {home.alt / 1000:.1f} m AMSL")

# Arming is refused until the EKF/GPS checks pass, so retry.
deadline = time.time() + 120
while not command(m, mav.MAV_CMD_COMPONENT_ARM_DISARM, 1):
    drain_statustext(m)
    if time.time() > deadline:
        fail("could not arm")
    time.sleep(2)
step("armed")

# PX4 NAV_TAKEOFF param7 is altitude AMSL.
if not command(m, mav.MAV_CMD_NAV_TAKEOFF, -1, 0, 0, math.nan, math.nan, math.nan,
               home.alt / 1000 + ALT):
    drain_statustext(m)
    fail("takeoff rejected")
pos = wait_until(m, lambda p: p.relative_alt >= (ALT - 1) * 1000,
                 "GLOBAL_POSITION_INT", 60, f"altitude {ALT - 1} m")
step(f"reached {pos.relative_alt / 1000:.1f} m")

if not command(m, mav.MAV_CMD_NAV_LAND, 0, 0, 0, math.nan, math.nan, math.nan, math.nan):
    fail("land rejected")
step("landing")
wait_until(m, lambda h: not armed(h), "HEARTBEAT", 90, "landing and auto-disarm")
step("landed and disarmed")

# --- API link: what MAVSDK / the OBC software sees ---
a = connect(API_URL)
step(f"API link: heartbeat from sys {a.target_system} ({API_URL})")
att = wait_until(a, lambda x: True, "ATTITUDE", 10, "ATTITUDE on API link")
step(f"API link: attitude roll {math.degrees(att.roll):.1f} pitch {math.degrees(att.pitch):.1f} deg")
step("PASS")
