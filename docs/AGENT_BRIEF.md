# Agent brief: ardu-docker-minimal

Goal: the smallest **working and configurable** ArduPilot SITL Docker image.
Approach (from "ArduPilot and Docker Part 2", discuss.ardupilot.org, pushed further):
Alpine builder, shallow clone with minimal submodules, `waf configure --board sitl --static`,
stripped static musl binary, final image `FROM scratch` + static busybox for an env-driven entrypoint.

## Pinned versions
- ArduPilot tag: `Copter-4.7.2` (build arg `AP_TAG`)
- Alpine: `3.20` (build arg `ALPINE_VERSION`)

## Image naming (always use these; always add the label)
- `ardu-min/builder:<alpine>`   toolchain only
- `ardu-min/src:<AP_TAG>`        builder + shallow source
- `ardu-min/sitl:<vehicle>`      final runtime image
- `ardu-min/test:latest`         pymavlink test client
- Every Dockerfile has `LABEL project=ardu-docker-minimal`.

## Rules
- Docker: this session's shell lacks the docker group. Run docker as `sg docker -c '<cmd>'`.
- The buildx plugin is missing, so use the classic builder: `DOCKER_BUILDKIT=0` and no `RUN --mount` / heredoc syntax.
- Only ONE docker build at a time. Builds may use `-j$(nproc)`.
- Never touch non-project docker resources. Clean up with `scripts/cleanup.sh` only.
  Never run `docker system prune -a` and never remove images not named `ardu-min/*`.
- No sudo, no apt, no pip installs on the host. Python tooling lives inside containers.
- If the same error happens 3 times, stop and report back with the log tail. Don't loop.
- Don't commit, branch or push; the tech lead does git (pushes via git@github.com:orcunkok/ardu-docker-minimal.git, HTTPS has no creds).
- Keep files short and commented like a minimal project. No over-engineering.
- Report: what you changed, exact commands run, image sizes (`docker image ls ardu-min/*`), and anything unverified.
