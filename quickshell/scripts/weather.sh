#!/usr/bin/env bash
# usage: weather.sh [location] [metric|imperial]   (location "" = auto by IP)
LOC="${1:-}"
UNITS="${2:-metric}"
KEY=$(printf '%s|%s' "$LOC" "$UNITS" | md5sum | cut -c1-8)
CACHE_FILE="/tmp/quickshell_weather_cache_$KEY.txt"

# Check cache age (15 mins = 900s)
if [ -f "$CACHE_FILE" ]; then
    NOW=$(date +%s)
    MTIME=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
    DIFF=$((NOW - MTIME))
    if [ $DIFF -lt 900 ]; then
        cat "$CACHE_FILE"
        exit 0
    fi
fi

# Fetch from wttr.in (m = metric, u = US units)
FLAG=m; [ "$UNITS" = "imperial" ] && FLAG=u
LOC_ENC=$(printf '%s' "$LOC" | sed 's/ /+/g')
WEATHER=$(curl -s --max-time 3 "wttr.in/${LOC_ENC}?${FLAG}&format=%t+%C" 2>/dev/null)
if [ -n "$WEATHER" ] && [ ${#WEATHER} -lt 40 ] && ! printf '%s' "$WEATHER" | grep -qi 'unknown location\|sorry'; then
    echo "$WEATHER" > "$CACHE_FILE"
    echo "$WEATHER"
else
    if [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
    else
        echo "+24°C Clear"
    fi
fi
