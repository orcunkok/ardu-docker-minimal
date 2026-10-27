# Progress / handoff log

Plan: /home/orcun/.claude/plans/i-wat-you-to-transient-hamster.md
Git: one branch per step `step/NN-name`, merged `--no-ff` into main, pushed (user allowed it for this repo).

| Step | Status | Notes |
|---|---|---|
| 01 scaffold | done | layout, brief, cleanup script |
| 02-05 build | done | alpine builder, shallow src, static musl, scratch runtime: 8.0 MB disk / 2.7 MB content |
| 06 tests | done | smoke test passes twice; fixes: /data chown, logs dir, re-assert GUIDED (RC mode switch resets mode at boot) |
| 07 multivehicle | done | plane/rover/sub images 7.5-8 MB; all 4 pass tests/run.sh; compose not runnable (no compose plugin) but equivalent 2x docker run verified |
| 08 docs | done | README, tag v0.1.0 |

## Notes for future work
- docker compose / buildx plugins are not installed on this host; everything uses the classic builder.
- Push via `git@github.com:orcunkok/ardu-docker-minimal.git` (HTTPS remote has no credentials).
- Runtime RAM measured ~2 MiB, CPU ~1.4% at SPEEDUP=1.
