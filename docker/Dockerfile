# Final SITL image (all vehicles live in the one Copter-4.7.2 repo checkout: copter|plane|rover|sub): static musl binary + static busybox on scratch.
ARG AP_TAG=Copter-4.7.2
FROM ardu-min/src:${AP_TAG} AS build
ARG VEHICLE=copter
RUN ./waf configure --board sitl --static && ./waf -j$(nproc) ${VEHICLE} \
 && strip -o /ardupilot-bin build/sitl/bin/ardu${VEHICLE} \
 && file /ardupilot-bin
# Root filesystem staged here because scratch has no shell to create links/dirs.
RUN mkdir -p /rootfs/usr/bin /rootfs/bin /rootfs/params/extra /rootfs/data/logs \
 && cp /ardupilot-bin /rootfs/usr/bin/ardupilot \
 && cp /bin/busybox.static /rootfs/bin/busybox \
 && ln -s busybox /rootfs/bin/sh \
 && chown -R 1000:1000 /rootfs/data

FROM scratch
LABEL project=ardu-docker-minimal
ARG VEHICLE=copter
ENV VEHICLE=${VEHICLE}
COPY --from=build /rootfs/ /
COPY params/${VEHICLE}.parm /params/defaults.parm
COPY docker/entrypoint.sh /entrypoint.sh
USER 1000:1000
WORKDIR /data
EXPOSE 5760 5762 5763
ENTRYPOINT ["/bin/sh","/entrypoint.sh"]
