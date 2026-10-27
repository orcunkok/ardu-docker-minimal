#!/bin/sh
# Maps env vars to ArduPilot SITL args (busybox sh, POSIX). Extra args are passed through.
# Default frame model per vehicle (from Tools/autotest/pysim/vehicleinfo.py); MODEL overrides.
case ${VEHICLE:-copter} in
  plane) MODEL=${MODEL:-plane};; rover) MODEL=${MODEL:-rover};;
  sub) MODEL=${MODEL:-vectored};; *) MODEL=${MODEL:-+};;
esac
HOME_LOC=${HOME_LOC:--35.363261,149.165230,584,353}
INSTANCE=${INSTANCE:-0}
SYSID=${SYSID:-1}
SPEEDUP=${SPEEDUP:-1}

# Defaults: base file plus every /params/extra/*.parm, comma-separated.
DEFAULTS=/params/defaults.parm
for f in /params/extra/*.parm; do [ -f "$f" ] && DEFAULTS="$DEFAULTS,$f"; done

set -- --model "$MODEL" --home "$HOME_LOC" -I "$INSTANCE" --sysid "$SYSID" \
       --speedup "$SPEEDUP" --defaults "$DEFAULTS" \
       ${SERIAL1:+--serial1 "$SERIAL1"} ${SERIAL2:+--serial2 "$SERIAL2"} "$@"

echo "+ /usr/bin/ardupilot $*"
exec /usr/bin/ardupilot "$@"
