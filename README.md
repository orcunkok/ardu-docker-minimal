# px4-x500 — a tiny, headless PX4 SITL in Docker

**PX4 software-in-the-loop simulation of a Holybro X500 V2 quadcopter in an ~11 MB Docker image.**
One `docker run` starts the simulated drone. It needs no Gazebo, no GPU and no display, and ground stations and companion-computer software can connect straight away over MAVLink.

| | |
|---|---|
| Image size | **10.9 MB** on disk, **3.6 MB** compressed |
| Memory | **~3.5 MiB** idle, ~6 MiB with a GCS connected |
| CPU | **~3–5 %** of one core idle, ~10 % with QGroundControl streaming |
| PX4 version | `v1.17.0` by default (any recent tag via a build arg) |
| Vehicle | Holybro X500 V2 (quad X), real PX4 X500 V2 gains |
| Physics | PX4's built-in **SIH** simulator, compiled into the PX4 binary |

Typical uses:
- CI tests for MAVLink / MAVSDK / MAVROS code
- developing companion-computer (OBC) software without a drone
- running many simulated drones on one machine
- GCS development
- teaching

For camera, lidar or obstacle simulation, use Gazebo instead (see [Trade-offs](#trade-offs)).

---

## Quick start

Requirements: Docker. Tested on Linux x86_64. Docker Desktop on macOS/Windows and arm64 hosts should work but are untested; see [Troubleshooting](#troubleshooting).

```sh
git clone <this-repo-url> px4-x500 && cd px4-x500
DOCKER_BUILDKIT=0 docker build -t px4-x500/sitl .        # first build: ~5-10 min, then cached
docker run --rm -p 18570:18570/udp -p 14580:14580/udp px4-x500/sitl
```
Wait for `Ready for takeoff!` in the log, then connect with any of the tools below.

`DOCKER_BUILDKIT=0` selects Docker's classic builder, so the build also works without the buildx plugin. If you have buildx, a plain `docker build` works too.

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
  -p 18570:18570/udp -p 14580:14580/udp px4-x500/sitl
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
| `HOME_LOC` | `47.397742,8.545594,488` | Start position `lat,lon,alt` (alt in m AMSL) |
| `SYSID` | `INSTANCE+1` | MAVLink system id (`MAV_SYS_ID`) |
| `INSTANCE` | `0` | PX4 instance; every port shifts by `+INSTANCE` |
| `SPEEDUP` | `1` | Simulation speed factor (`2` = twice real time) |
| `GCS_HOST` | unset | Push the GCS link to `host:14550` |
| `API_HOST` | unset | Push the API link to `host:14540` |
| `PX4_PARAM_<NAME>` | – | Set any PX4 parameter, e.g. `-e PX4_PARAM_MPC_XY_CRUISE=8` |

Any arguments after the image name are passed to the `px4` binary.

### Loading your own parameters
Mount a folder with one or more `*.params` files at `/params/extra`:
```sh
docker run --rm -v "$PWD/myparams:/params/extra:ro" -p 18570:18570/udp px4-x500/sitl
```
- **File format:** QGroundControl exports (*Vehicle Setup → Parameters → Tools → Save to file*) work as-is, and so do simple `NAME VALUE` lines. Files are applied in alphabetical order, after the X500 defaults.
- **Exports from a real flight controller are safe to use.** Hardware-only parameters are skipped so the simulation keeps working: sensor calibration and IDs (`CAL_*`, `SENS_*`, `*_ID`), serial and port setup (`SER_*`, `*_CONFIG`, `MAV_n_*`), outputs (`PWM_*`, `DSHOT_*`, `UAVCAN_*`), RC (`RC*`, `COM_RC_IN_MODE`), battery ADC scaling, `SYS_AUTOSTART` and `SIH_*`.
- **Keeping changes:** to keep parameter changes made from a GCS between runs, mount a volume at `/data`. That's the working directory, holding `parameters.bson` and the ULog flight logs in `/data/log`.

### Several drones
Give each container its own host ports and `SYSID`:
```sh
docker run -d -e SYSID=1 -p 18570:18570/udp -p 14580:14580/udp px4-x500/sitl
docker run -d -e SYSID=2 -e HOME_LOC=47.397742,8.546594,488 -p 18571:18570/udp -p 14581:14580/udp px4-x500/sitl
```
Or use the included `docker-compose.yml` (`docker compose up`), which starts two drones on 18570/14580 and 18571/14581. The compose file itself is untested; the equivalent `docker run` pair above is tested.

### PX4 version
Build any PX4 release by setting the tag. Ideally use the one flashed on your real flight controller:
```sh
DOCKER_BUILDKIT=0 docker build -t px4-x500/sitl --build-arg PX4_TAG=v1.16.2 .
```
SIH-as-SITL needs PX4 **v1.14 or newer**. Only v1.17.0 is tested; see [Contributing](#contributing) for what to check on other tags.

## How it works

```
alpine:3.20 build stage                          scratch runtime (~11 MB)
├─ toolchain (gcc, cmake, ninja, python deps)    ├─ /px4/bin/px4         static, stripped, 5.8 MB
├─ shallow PX4 clone + only needed submodules    ├─ /px4/bin/px4-*       module symlinks
├─ 3 small sed patches                           ├─ /px4/etc/            PX4 startup scripts, X500 airframe only
└─ make px4_sitl_default, linked -static         ├─ /bin/busybox         sh + the few tools rcS needs
                                                 └─ /entrypoint.sh       env vars → PX4
```
- **Physics:** PX4's **SIH** (simulation-in-hardware) module, which also runs in SITL, simulates rigid-body dynamics, IMU, GPS, baro and magnetometer inside the PX4 process. This makes it the PX4 counterpart of ArduPilot's built-in SITL physics. Everything else is the stock `px4_sitl_default` flight stack, with the same commander, EKF2, controllers, navigator and MAVLink.
- **The airframe** `10050_sihsim_x500` sets the SIH model to Holybro X500 V2 values:
  - 2.0 kg take-off weight
  - 500 mm wheelbase
  - inertia from PX4's Gazebo x500 model
  - ~9 N max thrust per motor, so it hovers at ~55 % throttle

  It uses the rate gains, gyro filter and rotor geometry from PX4's real hardware airframe `4019_x500_v2`.
- **Static musl binary + `FROM scratch`:** there's no libc, package manager or distro in the image, only one binary and a static busybox for the small shell entrypoint.
- **Build cache:** the first build compiles PX4 (~5–10 min). Rebuilds reuse the cached toolchain and source layers. `--no-cache` forces a full rebuild.

## Trade-offs

What you give up for 11 MB and near-zero CPU:

| Limitation | Details | If you need it |
|---|---|---|
| **No sensors beyond the basics** | SIH simulates IMU, GPS, baro and magnetometer only. There is no camera, depth, lidar, optical flow or rangefinder data. | Gazebo (`gz_x500_*` models), a separate image of ~1 GB+ |
| **No world** | Flat ground, no obstacles or terrain, no collisions with objects. | Gazebo |
| **Simplified aerodynamics** | First-order drag and a simple motor model, with no wind field, ground effect, prop wash or battery sag. Behaviour is close to an X500 but not identical. | Tune `SIH_*` in `10050_sihsim_x500`, or use Gazebo |
| **Estimated X500 numbers** | Mass, thrust and drag are estimated from published X500 V2 specs, not measured. Hover throttle and top speed will be in the right range but not exact. | Edit the `SIH_*` values for your build (motor/prop/battery) |
| **No flight-controller hardware** | Board drivers, ESCs, real sensor noise and timing aren't simulated. Only the PX4 software, airframe and parameters match a real drone. | HITL on the real board |
| **No RC transmitter** | The drone is flown over MAVLink only (`COM_RC_IN_MODE=4`). Manual flying uses a joystick through QGC (MAVLink `MANUAL_CONTROL`). | Remove the `COM_RC_IN_MODE` line in the airframe |
| **One vehicle type** | Only the X500 airframe is in the image. | Add an airframe file and change `PX4_SYS_AUTOSTART` in `entrypoint.sh` |
| **UDP only, client must talk first** | This is how PX4 SITL works, unlike ArduPilot SITL's TCP 5760. | Push mode (`GCS_HOST` / `API_HOST`) or `--network host` |
| **No ROS 2 agent inside** | PX4's uXRCE-DDS client runs and looks for an agent on `127.0.0.1:8888`, but no agent is included. | Run `MicroXRCEAgent` with `--network host` or in a sidecar container |
| **Custom musl build** | PX4 is officially built on glibc/Ubuntu. Building on musl needs one small source patch. | Use the official PX4 dev containers if you need upstream parity |
| **No `pxh>` shell** | PX4 runs as a daemon (`px4 -d`). | `docker exec <container> px4-param show MPC_*`, or any `px4-<module>` command |

## Testing

```sh
tests/run.sh
```
The test starts the simulator and checks both links:
- **GCS link (18570):** connect, wait for GPS, arm, take off to 10 m, land, auto-disarm.
- **API link (14580):** heartbeat and attitude.

It takes about 40 s. The client is a cached `python:3.12-slim` + pymavlink image that `run.sh` builds itself. The test also fails if the image grows beyond `MAX_MB` (default 30). Options:
- `EXTRA="-v $PWD/myparams:/params/extra:ro" tests/run.sh` tests with your own params.
- `SPEEDUP=2 tests/run.sh` runs the simulation at twice real time.

## Troubleshooting

| Symptom | Fix |
|---|---|
| QGC: *"bound address is already in use"* | The **Port** field in QGC's UDP link is QGC's own listening port. Don't use 14550 (QGC's auto-connect already holds it) or 18570 (Docker holds it on the host). Use e.g. `14551`, and put `127.0.0.1:18570` under *Server Addresses*. |
| No heartbeat at all | The client must send first (use `udpout:`), or use push mode. Check that the ports are published with `/udp`. |
| *"Arming denied: resolve system health failures"* | This is normal for the first few seconds while the EKF converges. Retry after `Ready for takeoff!`. |
| QGC doesn't auto-connect | Auto-connect needs PX4 to send to 14550: set `GCS_HOST`, plus `--add-host host.docker.internal:host-gateway` on Linux. |
| Push mode: `WARN: cannot resolve …` | The name isn't resolvable from inside the container. Use an IP, a container on the same Docker network, or `--add-host`. |
| Build fails at a `grep -c` check | A patch didn't apply on this `PX4_TAG`; see [Contributing](#contributing). |
| arm64 (Raspberry Pi, Jetson, Apple Silicon) | Nothing in the build is x86-specific. Build natively on the arm64 machine. This is untested so far; reports are welcome. |

## Repository layout

```
Dockerfile           build stage (toolchain, PX4 source, patches, compile) + scratch runtime
entrypoint.sh        env vars → PX4 environment, parameter import, push-mode targets
10050_sihsim_x500    the X500 V2 airframe (SIH physics + X500 gains)
docker-compose.yml   two-drone example
tests/               end-to-end flight test (run.sh + smoke_test.py)
```

Cleanup (everything this project creates has the label `project=px4-x500`):
```sh
docker ps -aq --filter label=project=px4-x500 | xargs -r docker rm -f
docker image prune -f --filter label=project=px4-x500
```

## Contributing

Issues and pull requests are welcome, in particular:
- arm64 test reports
- measured X500 thrust and drag values
- tests on other PX4 tags

The `Dockerfile` applies three small `sed` patches. When you bump `PX4_TAG`, they're the places to check, and the build fails loudly (`grep -c`) if one stops applying:
1. **`src/lib/rc/sbus.cpp`:** musl's `<sys/ioctl.h>` lacks `TCGETS2`/`TCSETS2`, so the patch defines them.
2. **`ROMFS/.../init.d-posix/airframes/CMakeLists.txt`:** registers `10050_sihsim_x500` after `10040_sihsim_quadx`.
3. **`ROMFS/.../init.d-posix/px4-rc.mavlink`:** adds `-t $PX4_GCS_IP` / `-t $PX4_API_IP` to the GCS and API `mavlink start` lines (push mode).

Implementation notes:
- `px4 -d` is required. Without a TTY, the interactive `pxh>` shell spins on EOF and floods the log.
- busybox `nslookup` appends the resolv.conf search domain, so the entrypoint looks up `name.` with a trailing dot.
- PX4's `rcS` sources the airframe *after* it sets `MAV_SYS_ID`. That's why user params and `SYSID` (`/data/rc.extra`) are applied at the end of the airframe file.

Please run `tests/run.sh` before opening a PR.

## Credits & license

- [PX4 Autopilot](https://github.com/PX4/PX4-Autopilot) and its SIH simulator ([docs](https://docs.px4.io/main/en/sim_sih/)) are BSD-3-Clause, © PX4 Development Team. The X500 V2 gains come from PX4's `4019_x500_v2` airframe.
- The approach of a static musl build on `FROM scratch` comes from the "ArduPilot and Docker" posts on discuss.ardupilot.org.
- Holybro and X500 are trademarks of Holybro. This project is not affiliated with Holybro or the PX4 project.
- The license for this repository's own files is in `LICENSE`.
