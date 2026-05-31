#!/bin/sh

STATS=$(vm_stat)
FREE=$(echo   "$STATS" | awk '/Pages free/                  {gsub(/\./,""); print $3}')
INACT=$(echo  "$STATS" | awk '/Pages inactive/              {gsub(/\./,""); print $3}')
ACTIVE=$(echo "$STATS" | awk '/Pages active/                {gsub(/\./,""); print $3}')
WIRED=$(echo  "$STATS" | awk '/Pages wired down/            {gsub(/\./,""); print $4}')
COMP=$(echo   "$STATS" | awk '/Pages occupied by compressor/{gsub(/\./,""); print $5}')

USED=$((ACTIVE + WIRED + COMP))
TOTAL=$((USED + FREE + INACT))
[ "$TOTAL" -le 0 ] && exit 0
PCT=$((USED * 100 / TOTAL))

sketchybar --set "$NAME" label="${PCT}%"
