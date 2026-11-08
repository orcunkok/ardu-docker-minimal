# 🛩️ tiny-sitl

**Drone autopilot simulators in Docker images smaller than a photo.**

Headless ArduPilot and PX4 SITL: one `docker run`, then connect QGroundControl, MAVProxy, MAVSDK or your own companion-computer code.

![ArduPilot](https://img.shields.io/badge/ArduPilot-Copter--4.7.2-0B7DBE)
![PX4](https://img.shields.io/badge/PX4-v1.17.0-E73E3A)
![image size](https://img.shields.io/badge/image-7.5--11_MB-2EA44F)
![RAM](https://img.shields.io/badge/RAM-2--6_MiB-2EA44F)
![base](https://img.shields.io/badge/base-FROM_scratch-555555)
![license](https://img.shields.io/badge/license-MIT-blue)


---

## 📦 One branch per image

Each image lives on its own branch with its own `Dockerfile`, README and end-to-end test. **`main` holds only this overview.**

| Branch | Autopilot | Vehicle | Disk | Compressed | RAM* | CPU* | MAVLink | Test |
|---|---|---|---|---|---|---|---|---|
| [`ardu-copter`](https://github.com/orcunkok/tiny-sitl/tree/ardu-copter) | ArduCopter | multicopter | **8.0 MB** | 2.7 MB | 2.8 MiB | 1.4 % | TCP 5760 / 5762 | ✈️ arm, takeoff 10 m, land |
| [`ardu-plane`](https://github.com/orcunkok/tiny-sitl/tree/ardu-plane) | ArduPlane | fixed-wing | **8.0 MB** | 2.7 MB | 2.1 MiB | 1.1 % | TCP 5760 / 5762 | arm, disarm |
| [`ardu-rover`](https://github.com/orcunkok/tiny-sitl/tree/ardu-rover) | ArduRover | rover / boat | **7.6 MB** | 2.5 MB | 2.3 MiB | 0.8 % | TCP 5760 / 5762 | arm, disarm |
| [`ardu-sub`](https://github.com/orcunkok/tiny-sitl/tree/ardu-sub) | ArduSub | ROV | **7.5 MB** | 2.5 MB | 2.3 MiB | 1.3 % | TCP 5760 / 5762 | arm, disarm |
| [`px4-x500`](https://github.com/orcunkok/tiny-sitl/tree/px4-x500) | PX4 | Holybro X500 V2 quad | **10.9 MB** | 3.6 MB | 5.6 MiB | 3.5 % | UDP 18570 / 14580 | ✈️ arm, takeoff 10 m, land |

> \* Measured on Linux x86_64 with a MAVLink client connected and streaming, at real-time speed. CPU is a percentage of one core.

For scale: a typical Ubuntu-based ArduPilot SITL image is **over 1.6 GB**, and the smallest image in the "ArduPilot and Docker" blog series was 12.6 MB.

## 🚀 Quick start

Pick a branch, build it once, run it:

```sh
git clone -b ardu-copter https://github.com/orcunkok/tiny-sitl.git && cd tiny-sitl
DOCKER_BUILDKIT=0 docker build -t ardu-copter/sitl .
docker run --rm -p 5760:5760 -p 5762:5762 ardu-copter/sitl
```

Then connect:

| | ArduPilot branches | PX4 branch |
|---|---|---|
| **Ground station** | TCP `127.0.0.1:5760` | UDP, server `127.0.0.1:18570` |
| **Companion / OBC software** | TCP `127.0.0.1:5762` | UDP `127.0.0.1:14580` |
| **MAVProxy** | `--master=tcp:127.0.0.1:5760` | `--master=udpout:127.0.0.1:18570` |
| **MAVSDK** | `tcpout://127.0.0.1:5762` | `udpout://127.0.0.1:14580` |
| **Auto-push to QGC on 14550** | `-e SERIAL1=udpclient:<host>:14550` | `-e GCS_HOST=<host>` |
| **Load your own params** | `*.parm` in `/params/extra` | QGC `*.params` in `/params/extra` |

Each branch's README has the full guide: all settings, several vehicles at once, push mode, troubleshooting and trade-offs.

## 🧩 How they stay this small

```
 Alpine (musl) build stage                     FROM scratch runtime
 ┌──────────────────────────────────┐          ┌──────────────────────────────┐
 │ toolchain only, no ARM gcc       │          │ 1 static, stripped binary    │
 │ shallow clone, minimal submodules│  ───▶    │ static busybox (sh)          │
 │ static link + strip              │          │ default params + entrypoint  │
 └──────────────────────────────────┘          └──────────────────────────────┘
        ~0.5–2 GB, cached                             7.5–11 MB, shipped
```
1. **No distro in the image.** `FROM scratch`: no libc, no package manager, no Python.
2. **One self-contained binary.** Static musl link, then `strip`.
3. **Physics compiled in.** ArduPilot's built-in SITL models, and PX4's SIH simulator, run inside the autopilot process. There's no Gazebo and no second process.
4. **Configured by env vars.** A tiny busybox entrypoint maps `HOME_LOC`, `SYSID`, `SPEEDUP` and so on to the autopilot's own options.
5. **Cached builds.** The toolchain and source layers build once, so rebuilds only recompile.

## ⚖️ Trade-offs (all branches)

| ✅ You get | ❌ You give up |
|---|---|
| Images of 8–11 MB that start in seconds | Cameras, lidar, depth and other rich sensors |
| RAM in the low single-digit MiB, ~1–4 % of a core | 3D worlds, obstacles and collisions (no Gazebo) |
| No GPU, no display, CI-friendly | High-fidelity aerodynamics, wind and battery sag |
| Dozens of vehicles on one laptop | Python tooling inside the image (`sim_vehicle.py`, MAVProxy) |
| The same autopilot code as the real flight controller | Flight-controller hardware (drivers, ESCs, real sensor noise) |

Good for: CI tests of MAVLink/MAVSDK/MAVROS code, developing companion-computer software, GCS development, swarm and fleet experiments, and teaching.
For vision or obstacle work, use Gazebo; it's a much larger image.

### ArduPilot vs PX4 branch, at a glance

| | ArduPilot branches | PX4 branch |
|---|---|---|
| Physics | ArduPilot built-in SITL models | PX4 SIH, tuned to the X500 V2 |
| Transport | TCP (UDP push optional) | UDP (push optional) |
| Starts simulating | When a client connects to 5760 | Immediately |
| Frames | Several per vehicle via `MODEL` | X500 V2 only |
| Build patches | None | 3 small `sed` patches (musl, airframe, push mode) |
| Tested flight | Copter: full flight; others: arm/disarm | Full flight + API link check |


## 🛠️ Requirements & status

- Docker, with or without buildx (`DOCKER_BUILDKIT=0` uses the classic builder).
- Tested on **Linux x86_64**. macOS/Windows Docker Desktop and arm64 should work but are untested; reports are welcome.

## 🤝 Contributing

Issues and PRs are welcome on the matching branch: new vehicles or frames, arm64 reports, newer autopilot versions, more test coverage.
Every branch has `tests/run.sh`; please run it before opening a PR.

## 📜 License & credits

The files in this repository (Dockerfiles, entrypoints, airframe, tests, docs) are released under the [MIT License](LICENSE).

The images you build *contain* third-party autopilot software, which keeps its own license:
- **ArduPilot** (`ardu-*` images) is [GPLv3](https://github.com/ArduPilot/ardupilot/blob/master/COPYING.txt). If you redistribute a built image, the GPL applies to that binary, including offering its source (the `AP_TAG` used).
- **PX4 Autopilot** (`px4-x500` image) is [BSD-3-Clause](https://github.com/PX4/PX4-Autopilot/blob/main/LICENSE).

Built on [ArduPilot](https://github.com/ArduPilot/ardupilot) and [PX4 Autopilot](https://github.com/PX4/PX4-Autopilot).
The approach grew out of "ArduPilot and Docker" [Part 1](https://discuss.ardupilot.org/t/ardupilot-and-docker-part-1/90532) and [Part 2](https://discuss.ardupilot.org/t/ardupilot-and-docker-part-2/98638).
Not affiliated with ArduPilot, PX4, Dronecode or Holybro.
