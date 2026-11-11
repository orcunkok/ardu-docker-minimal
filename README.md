# px4-x500 (px4 branch) — headless PX4 SITL in Docker, physics from your own simulator

**PX4 software-in-the-loop for a Holybro X500 V2 quadcopter in an ~11 MB Docker image, with no simulator inside.**
PX4 connects to an external flight-physics simulator over MAVLink HIL, the same interface Gazebo Classic and jMAVSim use. Ground stations and companion-computer software connect to the container over MAVLink as usual.

This is the `px4` branch. The `px4-x500` branch has the same image with PX4's built-in SIH physics, which needs no external sim.

| | |
|---|---|
| Image size | **~11 MB** on disk |
| PX4 version | `v1.17.0` by default (any recent tag via a build arg) |
| Vehicle | Holybro X500 V2 (quad X), real PX4 X500 V2 gains |
| Physics | **external**: PX4 is a TCP client to the sim on port `4560+INSTANCE` |

Typical uses:
- flight-dynamics work where you own the physics model (e.g. the dronstein sim)
- CI tests for MAVLink / MAVSDK / MAVROS code against your model
- running many simulated drones on one machine

---

## How it connects

```
  sim (Docker host)                         PX4 container
  TCP server 0.0.0.0:4560+INSTANCE  <-----  simulator_mavlink (TCP client, SIM_HOST)
     HIL_SENSOR 250 Hz, HIL_GPS 10 Hz  --->
     HIL_STATE_QUATERNION              --->
                                      <---  HIL_ACTUATOR_CONTROLS (motors 1-4 = controls[0..3])
                                            UDP 18570+INSTANCE  GCS link
                                            UDP 14580+INSTANCE  API / offboard link
```
- **Lockstep:** PX4's clock follows `HIL_SENSOR.time_usec`. PX4 does nothing until the sim sends sensor data, and the sim sets the speed.
- **Startup blocks** on the sim: PX4 logs `Waiting for simulator to accept connection on TCP port 4560` and retries until the sim listens. Start order doesn't matter.
- The sim also provides the home position (from its first `HIL_GPS`).

## Quick start

Requirements: Docker, and a sim listening on TCP 4560 on the Docker host. Tested on Docker Desktop, macOS arm64.

```sh
git clone <this-repo-url> px4-x500 && cd px4-x500 && git checkout px4
DOCKER_BUILDKIT=0 docker build -t px4-x500/px4 .        # first build: ~5-10 min, then cached
```
Start the sim, then PX4. With the dronstein sim:
```sh
cd ~/dev/dronstein && sim/.venv/bin/python sim/src        # TCP server on 4560
docker run --rm -p 18570:18570/udp -p 14580:14580/udp px4-x500/px4
```
Wait for `Simulator connected on TCP port 4560.` and then `Ready for takeoff!` in the log, then connect with any of the tools below.

`DOCKER_BUILDKIT=0` selects Docker's classic builder, so the build also works without the buildx plugin. If you have buildx, a plain `docker build` works too.

On Linux, add `--add-host host.docker.internal:host-gateway` (Docker Desktop provides `host.docker.internal` by itself), or set `SIM_HOST` to the sim's IP.

## Connecting

The simulator exposes the two standard PX4 SITL MAVLink links:

| Link | UDP port in the container | Use it for |
|---|---|---|
| **GCS** | `18570` | QGroundControl, MAVProxy |
| **API / offboard** | `14580` | MAVSDK, MAVROS, pymavlink, your own companion software |

There is no TCP port: PX4 SITL speaks MAVLink over UDP only. By default PX4 **replies to whoever sends it a packet first**, so the client has to send first. Every tool below does that when you point it at the port.

### QGroundControl
*Application Settings → Comm Links → Add*, type **UDP**:
- **Port**: leave it at a free port, e.g. `14551`. This is QGC's own *listening* port and must not be 14550 or 18570.
- **Server Addresses**: add `127.0.0.1:18570`.

Connect, and the X500 appears. To have QGC auto-connect with no link setup, use [push mode](#push-mode-px4-sends-first) instead.

### MAVProxy
```sh
mavproxy.py --master=udpout:127.0.0.1:18570
# MAV> mode takeoff / arm throttle / mode land ...
```

### MAVSDK (Python)
```sh
pip install "mavsdk<4"     # the classic gRPC API below; MAVSDK-Python 4.x has a new native API
```
```python
import asyncio
from mavsdk import System

async def main():
    drone = System()
    await drone.connect(system_address="udpout://127.0.0.1:14580")
    async for state in drone.core.connection_state():
        if state.is_connected:
            break
    async for health in drone.telemetry.health():
        if health.is_global_position_ok and health.is_home_position_ok:
            break
    await drone.action.arm()
    await drone.action.takeoff()
    await asyncio.sleep(15)
    await drone.action.land()

asyncio.run(main())
```
Tested with MAVSDK-Python 3.17. The same code also works with the `mavsdk-grpc` package (`import mavsdk_grpc as mavsdk`). If your MAVSDK version can only *listen* (`udp://:14540`), use push mode with `API_HOST`.

### pymavlink
```python
from pymavlink import mavutil
m = mavutil.mavlink_connection("udpout:127.0.0.1:14580", source_system=255)
m.mav.heartbeat_send(mavutil.mavlink.MAV_TYPE_GCS, mavutil.mavlink.MAV_AUTOPILOT_INVALID, 0, 0, 0)
print(m.wait_heartbeat())
```

### From another machine (e.g. a companion computer on the LAN)
Use the Docker host's IP instead of `127.0.0.1`, e.g. `udpout://192.168.1.20:14580`. MAVLink is plain UDP, so the client's CPU architecture and OS don't matter.

### Push mode (PX4 sends first)
Native PX4 SITL sends to 14550 (GCS) and 14540 (API) by itself. To get the same here, tell the container where to send:
```sh
docker run --rm --add-host host.docker.internal:host-gateway \
  -e GCS_HOST=host.docker.internal \
  -e API_HOST=192.168.1.50 \
  -p 18570:18570/udp -p 14580:14580/udp px4-x500/px4
```
- `GCS_HOST`: PX4 sends the GCS link to `GCS_HOST:14550`, so QGroundControl **auto-connects** with no link setup.
- `API_HOST`: PX4 sends the API link to `API_HOST:14540`, for software listening on `udpin://0.0.0.0:14540` (e.g. MAVSDK's `udp://:14540` or MAVROS' default `fcu_url`).
- Both accept an IP, a container name, or anything in `/etc/hosts`.
- `--add-host host.docker.internal:host-gateway` is only needed on Linux. Docker Desktop provides `host.docker.internal` by itself.
- On Linux, `--network host` is an alternative: the container then behaves exactly like native PX4 SITL on localhost.

## Configuration

All settings are environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `SIM_HOST` | `host.docker.internal` | Where the sim runs (name or IP). PX4 connects to `SIM_HOST:4560+INSTANCE` |
| `INSTANCE` | `0` | PX4 instance; every port shifts by `+INSTANCE` (sim TCP, GCS and API UDP) |
| `SYSID` | `INSTANCE+1` | MAVLink system id (`MAV_SYS_ID`) |
| `SPEEDUP` | `1` | Tell PX4 the sim runs this many times real time (scales its link-loss timeouts). The sim sets the actual speed |
| `GCS_HOST` | unset | Push the GCS link to `host:14550` |
| `API_HOST` | unset | Push the API link to `host:14540` |
| `PX4_PARAM_<NAME>` | – | Set any PX4 parameter, e.g. `-e PX4_PARAM_MPC_XY_CRUISE=8` |

Any arguments after the image name are passed to the `px4` binary.

### Loading your own parameters
Mount a folder with one or more `*.params` files at `/params/extra`:
```sh
docker run --rm -v "$PWD/myparams:/params/extra:ro" -p 18570:18570/udp px4-x500/px4
```
- **File format:** QGroundControl exports (*Vehicle Setup → Parameters → Tools → Save to file*) work as-is, and so do simple `NAME VALUE` lines. Files are applied in alphabetical order, after the X500 defaults.
- **Exports from a real flight controller are safe to use.** Hardware-only parameters are skipped so the simulation keeps working: sensor calibration and IDs (`CAL_*`, `SENS_*`, `*_ID`), serial and port setup (`SER_*`, `*_CONFIG`, `MAV_n_*`), outputs (`PWM_*`, `DSHOT_*`, `UAVCAN_*`), RC (`RC*`, `COM_RC_IN_MODE`), battery ADC scaling and `SYS_AUTOSTART`.
- **Keeping changes:** to keep parameter changes made from a GCS between runs, mount a volume at `/data`. That's the working directory, holding `parameters.bson` and the ULog flight logs in `/data/log`.

### Several drones
Run one sim per drone with its own instance, and give each container the same `INSTANCE`:
```sh
sim/.venv/bin/python sim/src --instance 0 &      # TCP 4560
sim/.venv/bin/python sim/src --instance 1 &      # TCP 4561
docker run -d -e INSTANCE=0 -p 18570:18570/udp -p 14580:14580/udp px4-x500/px4
docker run -d -e INSTANCE=1 -p 18571:18571/udp -p 14581:14581/udp px4-x500/px4
```
`SYSID` follows `INSTANCE` (1, 2, ...). Or use the included `docker-compose.yml` (`docker compose up`), which starts the same two drones. The compose file itself is untested.

### PX4 version
Build any PX4 release by setting the tag. Ideally use the one flashed on your real flight controller:
```sh
DOCKER_BUILDKIT=0 docker build -t px4-x500/px4 --build-arg PX4_TAG=v1.16.2 .
```
Only v1.17.0 is tested; see [Contributing](#contributing) for what to check on other tags.

## How it works

```
alpine:3.20 build stage                          scratch runtime (~11 MB)
├─ toolchain (gcc, cmake, ninja, python deps)    ├─ /px4/bin/px4         static, stripped, 5.8 MB
├─ shallow PX4 clone + only needed submodules    ├─ /px4/bin/px4-*       module symlinks
├─ 4 small sed patches                           ├─ /px4/etc/            PX4 startup scripts, X500 airframe only
└─ make px4_sitl_default, linked -static         ├─ /bin/busybox         sh + the few tools rcS needs
                                                 └─ /entrypoint.sh       env vars → PX4
```
- **No physics inside:** the build drops SIH and the simulated GPS/baro/mag/airspeed/AGP drivers from `px4_sitl_default`. PX4's `simulator_mavlink` module takes all sensor data from the external sim and sends motor outputs back. Everything else is the stock flight stack, with the same commander, EKF2, controllers, navigator and MAVLink. `battery_simulator` stays, so the battery drains as usual.
- **The airframe** `10050_x500` has the rate gains, gyro filter and rotor geometry from PX4's real hardware airframe `4019_x500_v2`, and maps motors 1-4 to `HIL_ACTUATOR_CONTROLS` `controls[0..3]`. Mass, thrust and drag live in the sim.
- **Static musl binary + `FROM scratch`:** there's no libc, package manager or distro in the image, only one binary and a static busybox for the small shell entrypoint.
- **Build cache:** the first build compiles PX4 (~5–10 min). Rebuilds reuse the cached toolchain and source layers. `--no-cache` forces a full rebuild.

## Trade-offs

What you give up for 11 MB and near-zero CPU:

| Limitation | Details | If you need it |
|---|---|---|
| **Needs a sim** | PX4 blocks at startup until something accepts TCP 4560+INSTANCE and sends `HIL_SENSOR`. | The `px4-x500` branch (SIH built in) |
| **Sensors and world are the sim's** | PX4 sees only what arrives as `HIL_SENSOR` / `HIL_GPS` (and `HIL_OPTICAL_FLOW`, `DISTANCE_SENSOR` if sent). | Extend the sim, or use Gazebo |
| **No flight-controller hardware** | Board drivers, ESCs, real sensor noise and timing aren't simulated. Only the PX4 software, airframe and parameters match a real drone. | HITL on the real board |
| **No RC transmitter** | The drone is flown over MAVLink only (`COM_RC_IN_MODE=1`, `NAV_RCL_ACT=0`). Manual flying uses a joystick through QGC (MAVLink `MANUAL_CONTROL`); auto modes need no sticks. | Remove those lines in the airframe |
| **One vehicle type** | Only the X500 airframe is in the image. | Add an airframe file and change `PX4_SYS_AUTOSTART` in `entrypoint.sh` |
| **UDP only, client must talk first** | This is how PX4 SITL works, unlike ArduPilot SITL's TCP 5760 (the sim link is outbound TCP). | Push mode (`GCS_HOST` / `API_HOST`) or `--network host` |
| **No ROS 2 agent inside** | PX4's uXRCE-DDS client runs and looks for an agent on `127.0.0.1:8888`, but no agent is included. | Run `MicroXRCEAgent` with `--network host` or in a sidecar container |
| **Custom musl build** | PX4 is officially built on glibc/Ubuntu. Building on musl needs one small source patch. | Use the official PX4 dev containers if you need upstream parity |
| **No `pxh>` shell** | PX4 runs as a daemon (`px4 -d`). | `docker exec <container> px4-param show MPC_*`, or any `px4-<module>` command |

## Testing

```sh
tests/run.sh                                                                      # sim already running
SIM_CMD="cd ~/dev/dronstein && sim/.venv/bin/python sim/src" tests/run.sh  # the script starts it
```
The test starts PX4 against the sim and checks both links:
- **GCS link (18570):** connect, wait for GPS, arm, take off to 10 m, land, auto-disarm.
- **API link (14580):** heartbeat and attitude.

`SIM_CMD` is run with `--instance $INSTANCE` appended and stopped at the end; its output goes to `tests/sim.log`. The client is a cached `python:3.12-slim` + pymavlink image that `run.sh` builds itself. The test also fails if the image grows beyond `MAX_MB` (default 30). Options:
- `INSTANCE=1 tests/run.sh` uses sim port 4561 and UDP 18571 / 14581.
- `SIM_HOST=192.168.1.30 tests/run.sh` when the sim runs elsewhere.
- `EXTRA="-v $PWD/myparams:/params/extra:ro" tests/run.sh` tests with your own params.

## Troubleshooting

| Symptom | Fix |
|---|---|
| QGC: *"bound address is already in use"* | The **Port** field in QGC's UDP link is QGC's own listening port. Don't use 14550 (QGC's auto-connect already holds it) or 18570 (Docker holds it on the host). Use e.g. `14551`, and put `127.0.0.1:18570` under *Server Addresses*. |
| Log stops at `Waiting for simulator to accept connection on TCP port 4560` | No sim listening on `SIM_HOST:4560+INSTANCE`. Start it bound to `0.0.0.0` (not `127.0.0.1`, which the container can't reach), check `INSTANCE` matches, and on Linux add `--add-host host.docker.internal:host-gateway`. |
| `WARN: cannot resolve host.docker.internal` | Linux without `--add-host host.docker.internal:host-gateway`; or set `SIM_HOST` to an IP. PX4 then falls back to localhost. |
| No heartbeat at all | The client must send first (use `udpout:`), or use push mode. Check that the ports are published with `/udp`. |
| *"Arming denied: resolve system health failures"* | This is normal for the first few seconds while the EKF converges. Retry after `Ready for takeoff!`. If it persists, the sim's sensor data is off (check the PX4 log for the failing check). |
| QGC doesn't auto-connect | Auto-connect needs PX4 to send to 14550: set `GCS_HOST`, plus `--add-host host.docker.internal:host-gateway` on Linux. |
| Push mode: `WARN: cannot resolve …` | The name isn't resolvable from inside the container. Use an IP, a container on the same Docker network, or `--add-host`. |
| Build fails at a `grep -c` check | A patch didn't apply on this `PX4_TAG`; see [Contributing](#contributing). |
| arm64 (Raspberry Pi, Jetson, Apple Silicon) | Nothing in the build is x86-specific. Build natively on the arm64 machine. Tested on Apple Silicon. |

## Repository layout

```
Dockerfile           build stage (toolchain, PX4 source, patches, compile) + scratch runtime
entrypoint.sh        env vars → PX4 environment, parameter import, push-mode targets
10050_x500           the X500 V2 airframe (X500 gains, external HIL sim)
docker-compose.yml   two-drone example
tests/               end-to-end flight test against the sim (run.sh + smoke_test.py)
```

Cleanup (everything this project creates has the label `project=px4-x500`):
```sh
docker ps -aq --filter label=project=px4-x500 | xargs -r docker rm -f
docker image prune -f --filter label=project=px4-x500
```

## Contributing

Issues and pull requests are welcome, in particular:
- arm64 test reports
- tests on other PX4 tags

The `Dockerfile` applies four small `sed` patches. When you bump `PX4_TAG`, they're the places to check, and the build fails loudly (`grep -c`) if one stops applying:
1. **`src/lib/rc/sbus.cpp`:** musl's `<sys/ioctl.h>` lacks `TCGETS2`/`TCSETS2`, so the patch defines them.
2. **`ROMFS/.../init.d-posix/airframes/CMakeLists.txt`:** registers `10050_x500` after `10040_sihsim_quadx`.
3. **`ROMFS/.../init.d-posix/px4-rc.mavlink`:** adds `-t $PX4_GCS_IP` / `-t $PX4_API_IP` to the GCS and API `mavlink start` lines (push mode).
4. **`boards/px4/sitl/default.px4board`:** replaces `CONFIG_COMMON_SIMULATION` (which pulls in SIH and the `*_SIM` sensor drivers) with `simulator_mavlink`, `battery_simulator` and `system_power_simulator`, and drops `SENSOR_AGP_SIM`.

Implementation notes:
- `px4 -d` is required. Without a TTY, the interactive `pxh>` shell spins on EOF and floods the log.
- Without `PX4_SIMULATOR` set and with `SYS_AUTOSTART` non-zero, PX4's `px4-rc.simulator` falls through to `px4-rc.mavlinksim`, which starts `simulator_mavlink -t $PX4_SIM_HOST_ADDR 4560+instance`. `-t` takes an IP only, so the entrypoint resolves `SIM_HOST` first.
- `px4-rc.mavlinksim` runs after the airframe and sets `EKF2_GPS_DELAY` to 10 by default, so the airframe uses `param set` for it.
- busybox `nslookup` appends the resolv.conf search domain, so the entrypoint looks up `name.` with a trailing dot.
- PX4's `rcS` sources the airframe *after* it sets `MAV_SYS_ID`. That's why user params and `SYSID` (`/data/rc.extra`) are applied at the end of the airframe file.

Please run `tests/run.sh` before opening a PR.

## Credits & license

- [PX4 Autopilot](https://github.com/PX4/PX4-Autopilot) is BSD-3-Clause, © PX4 Development Team. The X500 V2 gains come from PX4's `4019_x500_v2` airframe.
- The approach of a static musl build on `FROM scratch` comes from the "ArduPilot and Docker" posts on discuss.ardupilot.org.
- Holybro and X500 are trademarks of Holybro. This project is not affiliated with Holybro or the PX4 project.
- The license for this repository's own files is in `LICENSE`.
