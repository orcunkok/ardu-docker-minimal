# Toolchain only: Alpine (musl) + what the ArduPilot SITL waf build needs. No ARM toolchain.
ARG ALPINE_VERSION=3.20
FROM alpine:${ALPINE_VERSION}
LABEL project=ardu-docker-minimal
RUN apk add --no-cache build-base linux-headers git python3 py3-pip file busybox-static
RUN pip install --break-system-packages --no-cache-dir empy==3.3.4 pexpect future
