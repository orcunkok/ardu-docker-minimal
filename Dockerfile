# PX4 SITL, Holybro X500 V2 only: static musl px4 (SIH physics built in) + static busybox on scratch.
# Build: DOCKER_BUILDKIT=0 docker build -t px4-x500/sitl .   (--build-arg PX4_TAG=... to match the 6C)
FROM alpine:3.20 AS build
LABEL project=px4-x500
# Toolchain (cached; no ARM toolchain needed for SITL)
RUN apk add --no-cache build-base linux-headers cmake ninja git bash python3 py3-pip file busybox-static \
 && pip install --break-system-packages --no-cache-dir \
    "empy==3.3.4" jinja2 jsonschema kconfiglib pyyaml pyros-genmsg future packaging toml
# Shallow source with only the submodules px4_sitl_default needs (cached per PX4_TAG)
ARG PX4_TAG=v1.17.0
RUN git clone --depth 1 --branch ${PX4_TAG} https://github.com/PX4/PX4-Autopilot.git /px4
WORKDIR /px4
RUN git submodule update --init --depth 1 \
    src/modules/mavlink/mavlink src/drivers/gps/devices src/lib/events/libevents \
    src/lib/heatshrink/heatshrink src/modules/uxrce_dds_client/Micro-XRCE-DDS-Client \
    src/lib/cdrstream/cyclonedds src/lib/cdrstream/rosidl \
    src/lib/crypto/monocypher src/lib/crypto/libtomcrypt src/lib/crypto/libtommath \
 && git -C src/modules/mavlink/mavlink submodule update --init --recursive --depth 1
# Patches: musl lacks TCGETS2/TCSETS2 (sbus.cpp);
# let the GCS/API links push to a target IP (PX4_GCS_IP / PX4_API_IP, set by the entrypoint).
RUN sed -i "s|#include <asm-generic/termbits.h>|&\n#ifndef TCGETS2\n#define TCGETS2 _IOR('T', 0x2A, struct termios2)\n#define TCSETS2 _IOW('T', 0x2B, struct termios2)\n#endif|" src/lib/rc/sbus.cpp \
 && sed -i -e 's|^mavlink start -x -u $udp_gcs_port_local .*|& ${PX4_GCS_IP:+-t $PX4_GCS_IP}|' \
           -e 's|^mavlink start -x -u $udp_offboard_port_local .*|& ${PX4_API_IP:+-t $PX4_API_IP}|' \
           ROMFS/px4fmu_common/init.d-posix/px4-rc.mavlink \
 && grep -c 'TCGETS2 _IOR' src/lib/rc/sbus.cpp && grep -c 'PX4_GCS_IP\|PX4_API_IP' ROMFS/px4fmu_common/init.d-posix/px4-rc.mavlink
RUN CMAKE_ARGS="-DCMAKE_EXE_LINKER_FLAGS=-static" make px4_sitl_default \
 && strip -o /px4-bin build/px4_sitl_default/bin/px4 && file /px4-bin
# Root filesystem staged here because scratch has no shell to create links/dirs.
RUN B=build/px4_sitl_default R=/rootfs \
 && mkdir -p $R/px4/bin $R/bin $R/tmp $R/params/extra $R/data \
 && cp /px4-bin $R/px4/bin/px4 && cp $B/bin/px4-alias.sh $R/px4/bin/ \
 && for l in $B/bin/px4-*; do [ -L "$l" ] && ln -s px4 $R/px4/bin/$(basename $l); done \
 && cp -r $B/etc $R/px4/etc \
 && find $R/px4/etc/init.d-posix/airframes -type f -delete \
 && cp /bin/busybox.static $R/bin/busybox \
 && for a in sh bc basename dirname sed ls cp mv rm env awk nslookup cat mkdir grep tr cut expr sleep printf; do ln -s busybox $R/bin/$a; done \
 && chmod 1777 $R/tmp && chown -R 1000:1000 $R/data

FROM scratch
LABEL project=px4-x500
COPY --from=build /rootfs/ /
# The airframe goes in after the compile, so editing it rebuilds in seconds (rcS finds it by file name).
COPY 10050_sihsim_x500 /px4/etc/init.d-posix/airframes/
COPY entrypoint.sh /entrypoint.sh
ENV PATH=/px4/bin:/bin
USER 1000:1000
WORKDIR /data
# 18570 GCS link, 14580 API/offboard link (MAVSDK / OBC)
EXPOSE 18570/udp 14580/udp
ENTRYPOINT ["/bin/sh","/entrypoint.sh"]
