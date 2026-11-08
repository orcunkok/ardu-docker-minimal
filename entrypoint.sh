#!/bin/sh
# Maps env vars to PX4 SITL (Holybro X500 V2, SIH) env/params (busybox sh, POSIX). Extra args go to px4.
HOME_LOC=${HOME_LOC:-47.397742,8.545594,488}
INSTANCE=${INSTANCE:-0}
SYSID=${SYSID:-$((INSTANCE + 1))}
SPEEDUP=${SPEEDUP:-1}

export PX4_SYS_AUTOSTART=10050 PX4_SIMULATOR=sihsim PX4_SIM_MODEL=sihsim_x500
export PX4_HOME_LAT=${HOME_LOC%%,*}; r=${HOME_LOC#*,}
export PX4_HOME_LON=${r%%,*}; export PX4_HOME_ALT=${r#*,}
[ "$SPEEDUP" != 1 ] && export PX4_SIM_SPEED_FACTOR=$SPEEDUP

# Host name or IP -> IP (mavlink -t only takes an IP). /etc/hosts first (extra_hosts), then DNS (trailing dot: busybox would append the search domain).
resolve() {
  case $1 in *[!0-9.]*) ;; *) echo "$1"; return;; esac
  ip=$(awk -v h="$1" '{for (i = 2; i <= NF; i++) if ($i == h) {print $1; exit}}' /etc/hosts)
  [ -n "$ip" ] || ip=$(nslookup -type=a "${1%.}." 2>/dev/null | awk '/^Name:/ {n = 1} n && /^Address/ {print $NF; exit}')
  [ -n "$ip" ] || echo "WARN: cannot resolve $1" >&2
  echo "$ip"
}
[ -n "$GCS_HOST" ] && export PX4_GCS_IP=$(resolve "$GCS_HOST")
[ -n "$API_HOST" ] && export PX4_API_IP=$(resolve "$API_HOST")

# Params: every /params/extra/*.params (QGC export or "NAME VALUE" lines).
# Hardware-only params from a real Pixhawk export are skipped (calibration, sensors, ports, RC, ids).
SKIP='^(CAL_|SENS_|SIH_|PWM_|SER_|RC|COM_RC_IN_MODE$|MAV_[0-9]_|UAVCAN_|DSHOT_|SYS_AUTOSTART$|SYS_AUTOCONFIG$|SYS_HAS_|BAT[0-9]_(V_DIV|A_PER_V|SOURCE|V_CHANNEL|I_CHANNEL)$)|_ID$|_CONFIG$'
: > /data/rc.extra
for f in /params/extra/*.params; do
  [ -f "$f" ] || continue
  awk -v skip="$SKIP" '!/^[[:space:]]*(#|$)/ {
      if (NF >= 4) { n = $3; v = $4 } else { n = $1; v = $2 }
      if (n !~ skip) print "param set " n " " v }' "$f" >> /data/rc.extra
done
echo "param set MAV_SYS_ID $SYSID" >> /data/rc.extra

set -- -d -w /data -i "$INSTANCE" /px4/etc "$@"
echo "+ px4 $* (SYSID=$SYSID home=$HOME_LOC gcs=${PX4_GCS_IP:-reply} api=${PX4_API_IP:-reply})"
exec /px4/bin/px4 "$@"
