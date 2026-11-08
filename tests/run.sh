#!/bin/sh
# End-to-end smoke test: start the PX4 X500 SITL container, fly it with a pymavlink client.
# Usage: tests/run.sh
set -eu
IMAGE=px4-x500/sitl:latest
EXTRA=${EXTRA:-}  # extra docker run args, e.g. -v ./x:/params/extra:ro
MAX_MB=${MAX_MB:-30}
NET=px4-x500-test
SITL=px4-x500-sitl
cd "$(dirname "$0")"

cleanup() {
  docker rm -f "$SITL" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
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
docker network create "$NET" >/dev/null
docker run -d --name "$SITL" --network "$NET" --label project=px4-x500 \
  -e SPEEDUP="${SPEEDUP:-1}" $EXTRA "$IMAGE" >/dev/null
if ! docker run --rm --network "$NET" --label project=px4-x500 -v "$PWD/smoke_test.py:/smoke_test.py:ro" \
     -e MAV_URL="udpout:$SITL:18570" -e API_URL="udpout:$SITL:14580" px4-x500/test:latest python3 /smoke_test.py; then
  echo "--- SITL log tail ---"; docker logs --tail 40 "$SITL"; exit 1
fi
