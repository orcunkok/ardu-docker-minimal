# Project summary: ardu-docker-minimal (v0.1.0)

## Goal
Build the smallest ArduPilot SITL Docker image that works and can be configured, with a minimal test of connect, arm, takeoff and land.

## Result
| Image | Disk | Compressed | Test |
|---|---|---|---|
| `ardu-min/sitl:copter` | 8.0 MB | 2.7 MB | full flight: GUIDED, arm, takeoff 10 m, LAND, disarmed |
| `ardu-min/sitl:plane` | 8.0 MB | 2.7 MB | connect, arm, disarm |
| `ardu-min/sitl:rover` | 7.6 MB | 2.5 MB | connect, arm, disarm |
| `ardu-min/sitl:sub` | 7.5 MB | 2.5 MB | connect, arm, disarm |

- ArduPilot source: `Copter-4.7.2`. All vehicles are built from the same commit.
- Runtime footprint: about 2 MiB RAM and about 1.4% CPU at `SPEEDUP=1`.
- For reference, the smallest image in "ArduPilot and Docker" Part 2 (Alpine) was 12.6 MB, and the default Ubuntu image is more than 1.6 GB.

## How it is so small
1. **Alpine (musl) builder** with no ARM/STM32 toolchain (the blog's `DO_AP_STM_ENV=0` idea). The builder is 453 MB.
2. **Shallow clone** (`--depth 1`) with only the 8 submodules SITL needs: mavlink, waf, littlefs, lwip, and 4 DroneCAN modules.
3. **Static build**: `waf configure --board sitl --static`, then `strip`. The result is one self-contained binary.
4. **`FROM scratch` runtime**: just the binary, a static busybox (for the env-var entrypoint), default params and the entrypoint script.
5. **Separately tagged stages** (`builder`, `src`, `sitl`): the toolchain and clone are built once, so a rebuild only redoes the waf step.

## Step history (one git branch per step, merged `--no-ff` into main)
| Step | Branch | What |
|---|---|---|
| 01 | `step/01-scaffold` | layout, agent brief, project-scoped cleanup script |
| 02 | `step/02-builder` | Alpine builder image |
| 03 | `step/03-source` | shallow source with minimal submodules |
| 04 | `step/04-build-static` | static musl build, `scripts/build.sh` |
| 05 | `step/05-runtime-scratch` | scratch runtime, entrypoint, default params |
| 06 | `step/06-tests` | pymavlink smoke test; fixes for `/data` ownership and the logs dir |
| 07 | `step/07-multivehicle` | plane/rover/sub, vehicle-aware tests, compose example |
| 08 | `step/08-docs` | README, tag `v0.1.0` |

## Problems found and fixed
- **"Param storage failed"**: `/data` was owned by root, so eeprom.bin could not be written. Fixed by chowning it in the build stage.
- **"Log open fail"**: the `logs/` directory was missing. It is now created in the image.
- **Takeoff rejected (result 4)**: the RC mode switch reset the flight mode to STABILIZE during boot. The test now re-sets GUIDED before every arming attempt.
- **Stale COMMAND_ACK**: the test now waits for the ACK that matches the command it sent.

## Known limits and open items
- The image has no Python, `sim_vehicle.py` or MAVProxy. Use a GCS or MAVProxy outside the container.
- `docker-compose.yml` was not run because the compose plugin is not installed on the build host. The same 2-instance setup was checked with plain `docker run` (ports 5760 and 5770 both open).
- The plane, rover and sub tests only arm and disarm. They do not fly.
- SERIAL1/SERIAL2 `udpclient` output is documented but not tested end to end.
- The classic builder is used because buildx is not installed. It prints a deprecation warning, which does no harm.

## Quick start
```sh
scripts/build.sh copter            # about 5 min the first time (builder + src), then about 1 min per vehicle
tests/run.sh copter                # about 80 s, prints PASS
docker run --rm -p 5760:5760 ardu-min/sitl:copter
```
See [README.md](../README.md) for the configuration table, and [PROGRESS.md](PROGRESS.md) for the build log.
