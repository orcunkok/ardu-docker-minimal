#!/bin/sh
# Usage: scripts/build.sh [vehicle] [--rebuild]   Builds builder -> src -> sitl.
set -eu
cd "$(dirname "$0")/.."
VEHICLE=copter; REBUILD=0
for a in "$@"; do case "$a" in --rebuild) REBUILD=1;; *) VEHICLE=$a;; esac; done
AP_TAG=${AP_TAG:-Copter-4.7.2}; ALPINE_VERSION=${ALPINE_VERSION:-3.20}
export DOCKER_BUILDKIT=0
build() { # tag, dockerfile, args...
  t=$1; f=$2; shift 2
  if [ $REBUILD = 0 ] && [ "$t" != "ardu-min/sitl:$VEHICLE" ] && docker image inspect "$t" >/dev/null 2>&1; then
    echo "skip $t (exists)"; return; fi
  docker build -t "$t" -f "$f" "$@" .
}
build ardu-min/builder:$ALPINE_VERSION docker/builder.Dockerfile --build-arg ALPINE_VERSION=$ALPINE_VERSION
build ardu-min/src:$AP_TAG docker/src.Dockerfile --build-arg AP_TAG=$AP_TAG
build ardu-min/sitl:$VEHICLE docker/Dockerfile --build-arg AP_TAG=$AP_TAG --build-arg VEHICLE=$VEHICLE
docker image ls 'ardu-min/*'
