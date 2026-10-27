#!/bin/sh
# Project-scoped docker cleanup. Never touches images outside ardu-min/*.
set -u
# Stopped containers from this project
docker ps -aq --filter label=project=ardu-docker-minimal --filter status=exited | xargs -r docker rm >/dev/null
# Dangling layers left by rebuilds of our images
docker image prune -f --filter label=project=ardu-docker-minimal >/dev/null
# Optional: remove intermediate stages (keep final runtime + test images)
if [ "${1:-}" = "--intermediate" ]; then
  docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -E '^ardu-min/(builder|src|build):' | xargs -r docker rmi >/dev/null
fi
docker system df
