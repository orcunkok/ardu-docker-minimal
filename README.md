# ardu-docker-minimal

The smallest working, configurable ArduPilot SITL Docker image: about **8 MB on disk (2.7 MB compressed)**, and about **2 MiB RAM** at runtime.

It builds on the ideas in "ArduPilot and Docker" [Part 1](https://discuss.ardupilot.org/t/ardupilot-and-docker-part-1/90532) / [Part 2](https://discuss.ardupilot.org/t/ardupilot-and-docker-part-2/98638) and pushes them further:

| Technique | Effect |
|---|---|
| Alpine (musl) builder, no ARM/STM32 toolchain (the blog's `DO_AP_STM_ENV=0` idea) | builder 453 MB |
| `--depth 1` clone + only 8 needed submodules | source layer stays cached, never in the final image |
| `waf configure --board sitl --static` + `strip` | one self-contained binary, no libc needed |
| `FROM scratch` + static busybox (only for the env-var entrypoint) | final image ~8 MB |
| Separately tagged stages (`builder` → `src` → `sitl`) | toolchain and clone are built once; vehicle rebuilds take only the waf step |

Images (ArduPilot `Copter-4.7.2` source; all vehicles come from the same commit):

| Image | Disk | Compressed |
|---|---|---|
| `ardu-min/sitl:copter` | 8.0 MB | 2.7 MB |
| `ardu-min/sitl:plane` | 8.0 MB | 2.7 MB |
| `ardu-min/sitl:rover` | 7.6 MB | 2.5 MB |
| `ardu-min/sitl:sub` | 7.5 MB | 2.5 MB |

## Build
```sh
scripts/build.sh copter          # or plane | rover | sub ; --rebuild to redo builder/src
AP_TAG=Copter-4.7.2 scripts/build.sh copter
```
The classic `docker build` is enough; buildx is not needed.

## Run
```sh
docker run --rm -p 5760:5760 ardu-min/sitl:copter
mavproxy.py --master=tcp:127.0.0.1:5760       # or QGroundControl / Mission Planner → TCP 5760
```
SITL waits for the first connection on 5760 (SERIAL0) before the simulation starts. SERIAL1 and SERIAL2 listen on TCP 5762 and 5763 by default.

### Configuration
| Env var | Default | Meaning |
|---|---|---|
| `MODEL` | per vehicle: `+`, `plane`, `rover`, `vectored` | SITL frame (`--model`) |
| `HOME_LOC` | `-35.363261,149.165230,584,353` | lat,lon,alt,heading (`--home`) |
| `SYSID` | `1` | MAVLink system id |
| `INSTANCE` | `0` | `-I`, ports shift by +10 per instance |
| `SPEEDUP` | `1` | simulation speed |
| `SERIAL1`, `SERIAL2` | unset | e.g. `udpclient:192.168.1.10:14550` |

- Extra parameters: mount any `*.parm` files into `/params/extra/`, e.g. `-v $PWD/my:/params/extra:ro`. They are applied after the vehicle defaults.
- Any extra arguments after the image name are passed straight to the SITL binary.
- `/data` is the working directory (eeprom, logs). Mount a volume there to keep parameters between runs.
- The container runs as uid 1000.

Two vehicles at once (see `docker-compose.yml`):
```sh
docker compose up        # copter1 on 5760 (SYSID 1), copter2 on 5770 (SYSID 2)
```

## Test
```sh
tests/run.sh copter      # connect → GUIDED → arm → takeoff 10 m → LAND → disarmed  (~80 s)
tests/run.sh plane       # plane/rover/sub: connect → arm → disarm
```
The test client is a separate `python:3.12-slim` + pymavlink image (`ardu-min/test`). It also fails if the SITL image grows beyond `MAX_MB` (default 15).

## Cleanup
```sh
scripts/cleanup.sh                  # project containers + dangling layers only
scripts/cleanup.sh --intermediate   # also remove builder/src (~2.4 GB), rebuilt on demand
```

## Trade-offs
- No Python, `sim_vehicle.py` or MAVProxy inside the image. Use a GCS or MAVProxy on the host or in another container.
- No RC input. If you need simulated sticks, use RC_OVERRIDE or MAVProxy `--sitl`. The RC mode switch can reset the flight mode during boot, so set the mode after the vehicle reports it is ready (the test handles this).
- No terrain data download (no network tooling in the image).
