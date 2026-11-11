#!/bin/sh
# End-to-end smoke test: start the PX4 X500 container against an external sim, fly it with a pymavlink client.
# Usage: tests/run.sh                      (sim already listening on TCP 4560+INSTANCE on the Docker host)
#        SIM_CMD="cd ~/dev/dronstein && sim/.venv/bin/python sim/src" tests/run.sh
set -eu
IMAGE=px4-x500/px4:latest
EXTRA=${EXTRA:-}  # extra docker run args, e.g. -v ./x:/params/extra:ro
MAX_MB=${MAX_MB:-30}
INSTANCE=${INSTANCE:-0}
SIM_HOST=${SIM_HOST:-host.docker.internal}
SIM_CMD=${SIM_CMD:-}  # started here (with --instance $INSTANCE) and stopped on exit
NET=px4-x500-test
SITL=px4-x500-px4
cd "$(dirname "$0")"
sim_pid=

cleanup() {
  docker rm -f "$SITL" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  [ -z "$sim_pid" ] || { pkill -P "$sim_pid"; kill "$sim_pid"; } 2>/dev/null || true
}
trap cleanup EXIT

size=$(docker image inspect -f '{{.Size}}' "$IMAGE")
echo "image $IMAGE: $((size / 1000000)) MB content size (limit $MAX_MB MB)"
[ "$size" -le $((MAX_MB * 1000000)) ] || { echo "FAIL: image too large"; exit 1; }

# Test client image (cached after the first run); smoke_test.py is mounted, not copied.
DOCKER_BUILDKIT=0 docker build -q -t px4-x500/test:latest - >/dev/null <<'DOCKERFILE'
FROM python:3.12-slim
LABEL project=px4-x500
RUN pip install --no-cache-dir pymavlink==2.4.43
ENV MAVLINK20=1 MAVLINK_DIALECT=common PYTHONUNBUFFERED=1
DOCKERFILE

cleanup
if [ -n "$SIM_CMD" ]; then
  sh -c "$SIM_CMD --instance $INSTANCE" > sim.log 2>&1 &
  sim_pid=$!
  echo "sim: $SIM_CMD --instance $INSTANCE (pid $sim_pid, log tests/sim.log)"
fi
docker network create "$NET" >/dev/null
# host-gateway: host.docker.internal on Linux (Docker Desktop has it anyway).
docker run -d --name "$SITL" --network "$NET" --label project=px4-x500 --add-host host.docker.internal:host-gateway \
  -e INSTANCE="$INSTANCE" -e SIM_HOST="$SIM_HOST" -e SPEEDUP="${SPEEDUP:-1}" $EXTRA "$IMAGE" >/dev/null
if ! docker run --rm --network "$NET" --label project=px4-x500 -v "$PWD/smoke_test.py:/smoke_test.py:ro" \
     -e MAV_URL="udpout:$SITL:$((18570 + INSTANCE))" -e API_URL="udpout:$SITL:$((14580 + INSTANCE))" \
     px4-x500/test:latest python3 /smoke_test.py; then
  echo "--- PX4 log tail ---"; docker logs --tail 40 "$SITL"
  [ -z "$sim_pid" ] || { echo "--- sim log tail ---"; tail -20 sim.log; }
  exit 1
fi
