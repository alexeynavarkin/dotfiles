#!/bin/sh

CACHE="/tmp/sketchybar_cpu"
PIDFILE="/tmp/sketchybar_cpu.pid"
# Distinctive argv used only by our daemon — safe target for pkill -f.
TOP_ARGV="top -l 0 -n 0 -s 2"

ensure_daemon() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    return
  fi
  # Reap any orphaned top from prior daemon (sh wrapper died, top survived).
  pkill -f "^${TOP_ARGV}$" 2>/dev/null
  nohup sh -c "
    exec $TOP_ARGV | awk -v out='$CACHE' '
      /^CPU usage/ {
        gsub(/%/, \"\")
        printf \"%d\", \$3 + \$5 > out
        close(out)
      }
    '
  " >/dev/null 2>&1 &
  echo $! > "$PIDFILE"
}

ensure_daemon

if [ -s "$CACHE" ]; then
  VAL=$(cat "$CACHE")
  sketchybar --set "$NAME" label="${VAL}%"
else
  sketchybar --set "$NAME" label="--"
fi
