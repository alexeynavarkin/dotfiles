#!/bin/sh
# Claude Code status line — mirrors PS1:
#   user@host (bold green) | git branch | cwd | context % | today % | week % | model

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five_hour=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_hour_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_day=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_day_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# context usage indicator
ctx_part=""
if [ -n "$used" ]; then
  ctx_part=" | ctx:$(printf '%.0f' "$used")%"
fi

# rate limit indicators (Claude.ai subscription)
rate_part=""
if [ -n "$five_hour" ] || [ -n "$seven_day" ]; then
  today_str=""
  week_str=""
  if [ -n "$five_hour" ]; then
    five_reset_str=""
    if [ -n "$five_hour_resets" ]; then
      five_reset_str=" rst $(date -r "$five_hour_resets" +%H:%M 2>/dev/null)"
    fi
    today_str="5h:$(printf '%.0f' "$five_hour")%${five_reset_str}"
  fi
  if [ -n "$seven_day" ]; then
    week_reset_str=""
    if [ -n "$seven_day_resets" ]; then
      week_reset_str=" rst $(date -r "$seven_day_resets" '+%a %H:%M' 2>/dev/null)"
    fi
    week_str="7d:$(printf '%.0f' "$seven_day")%${week_reset_str}"
  fi
  if [ -n "$today_str" ] && [ -n "$week_str" ]; then
    rate_part=" | $today_str | $week_str"
  elif [ -n "$today_str" ]; then
    rate_part=" | $today_str"
  else
    rate_part=" | $week_str"
  fi
fi

# model
model_part="$model"

printf '%s%s%s' \
  "$model_part" \
  "$ctx_part" \
  "$rate_part"

