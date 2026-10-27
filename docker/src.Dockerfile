# Builder + shallow ArduPilot source with only the submodules SITL copter needs.
FROM ardu-min/builder:3.20
LABEL project=ardu-docker-minimal
ARG AP_TAG=Copter-4.7.2
RUN git clone --depth 1 --branch ${AP_TAG} https://github.com/ArduPilot/ardupilot.git /ardupilot
WORKDIR /ardupilot
RUN git submodule update --init --depth 1 \
    modules/mavlink modules/waf \
    modules/DroneCAN/libcanard modules/DroneCAN/DSDL modules/DroneCAN/dronecan_dsdlc modules/DroneCAN/pydronecan modules/littlefs modules/lwip

