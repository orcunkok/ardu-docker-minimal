#!/bin/sh
# End-to-end smoke test: start SITL container, fly it with the pymavlink client.
# Usage: tests/run.sh [vehicle]   (default copter)
set -eu
VEHICLE=${1:-copter}
IMAGE=ardu-min/sitl:$VEHICLE
MAX_MB=${MAX_MB:-15}
NET=ardu-min-test
SITL=ardu-min-sitl
cd "$(dirname "$0")"

cleanup() {
  docker rm -f "$SITL" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

size=$(docker image inspect -f '{{.Size}}' "$IMAGE")
echo "image $IMAGE: $((size / 1000000)) MB content size (limit $MAX_MB MB)"
[ "$size" -le $((MAX_MB * 1000000)) ] || { echo "FAIL: image too large"; exit 1; }

docker build -q -t ardu-min/test:latest . >/dev/null
cleanup
docker network create "$NET" >/dev/null
docker run -d --name "$SITL" --network "$NET" --label project=ardu-docker-minimal \
  -e SPEEDUP="${SPEEDUP:-1}" "$IMAGE" >/dev/null
if ! docker run --rm --network "$NET" --label project=ardu-docker-minimal \
     -e MAV_URL="tcp:$SITL:5760" ardu-min/test:latest; then
  echo "--- SITL log tail ---"; docker logs --tail 40 "$SITL"; exit 1
fi
