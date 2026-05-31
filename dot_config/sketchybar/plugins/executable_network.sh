#!/bin/sh

INTERVAL=2
CACHE="/tmp/sketchybar_net_sum"
IF_CACHE="/tmp/sketchybar_net_ifaces"
IF_TTL=60

# Physical interfaces only: Wi-Fi + Ethernet/LAN adapters from networksetup.
# Cached for $IF_TTL seconds — list changes rarely (USB plug, new adapter).
if [ ! -f "$IF_CACHE" ] || [ $(( $(date +%s) - $(stat -f %m "$IF_CACHE") )) -ge "$IF_TTL" ]; then
  networksetup -listallhardwareports 2>/dev/null | awk '
    /^Hardware Port:/ { port = substr($0, index($0,$3)); next }
    /^Device:/ {
      if (port ~ /Wi-Fi/ || port ~ /Ethernet/ || port ~ /^AX[0-9]/ || port ~ /USB.*(LAN|Ethernet)/)
        print $2
    }' > "$IF_CACHE"
fi
IFACES=$(cat "$IF_CACHE")

SUM_IN=0
SUM_OUT=0
for IF in $IFACES; do
  # Skip if interface is not active (no link)
  ifconfig "$IF" 2>/dev/null | grep -q "status: active" || continue
  LINE=$(netstat -ibn | awk -v i="$IF" '$1==i && $4!~/Link/ {print $7, $10; exit}')
  [ -z "$LINE" ] && continue
  IN=$(echo  "$LINE" | awk '{print $1}')
  OUT=$(echo "$LINE" | awk '{print $2}')
  SUM_IN=$((SUM_IN + IN))
  SUM_OUT=$((SUM_OUT + OUT))
done

if [ "$SUM_IN" -eq 0 ] && [ "$SUM_OUT" -eq 0 ]; then
  sketchybar --set network.down label="--" --set network.up label="--"
  exit 0
fi

if [ -f "$CACHE" ]; then
  PREV=$(cat "$CACHE")
  PREV_IN=$(echo  "$PREV" | awk '{print $1}')
  PREV_OUT=$(echo "$PREV" | awk '{print $2}')
  DOWN=$(( (SUM_IN  - PREV_IN ) / INTERVAL ))
  UP=$((   (SUM_OUT - PREV_OUT) / INTERVAL ))
  [ "$DOWN" -lt 0 ] && DOWN=0
  [ "$UP"   -lt 0 ] && UP=0
else
  DOWN=0
  UP=0
fi
echo "$SUM_IN $SUM_OUT" > "$CACHE"

human() {
  b=$1
  if   [ "$b" -ge 1048576 ]; then printf "%.1fM" "$(echo "$b/1048576" | bc -l)"
  elif [ "$b" -ge 1024 ];    then printf "%dK"   "$((b/1024))"
  else                            printf "%dB"   "$b"
  fi
}

sketchybar --set network.down label="$(human "$DOWN")" \
           --set network.up   label="$(human "$UP")"
