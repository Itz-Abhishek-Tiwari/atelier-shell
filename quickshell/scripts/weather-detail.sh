#!/usr/bin/env bash
# usage: weather-detail.sh [location] [metric|imperial]   → one JSON object (wttr.in j1, cached 15 min)
LOC="${1:-}"; UNITS="${2:-metric}"
KEY=$(printf '%s|%s' "$LOC" "$UNITS" | md5sum | cut -c1-8)
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/atelier/weather-$KEY.json"
mkdir -p "$(dirname "$CACHE")"
if [ -f "$CACHE" ] && [ $(( $(date +%s) - $(stat -c %Y "$CACHE") )) -lt 900 ]; then cat "$CACHE"; exit 0; fi
RAW=$(curl -s --max-time 6 "wttr.in/$(printf '%s' "$LOC" | sed 's/ /+/g')?format=j1" 2>/dev/null)
OUT=$(printf '%s' "$RAW" | python3 -I -c '
import json, sys
units = sys.argv[1]
try:
    d = json.load(sys.stdin)
    c = d["current_condition"][0]
    imp = units == "imperial"
    t, ft, w = ("temp_F", "FeelsLikeF", "windspeedMiles") if imp else ("temp_C", "FeelsLikeC", "windspeedKmph")
    days = []
    for x in d["weather"][:3]:
        h = x["hourly"][4]
        days.append({"date": x["date"], "max": x["maxtemp" + ("F" if imp else "C")], "min": x["mintemp" + ("F" if imp else "C")],
                     "desc": h["weatherDesc"][0]["value"], "code": int(h["weatherCode"]), "rain": int(h["chanceofrain"])})
    area = d.get("nearest_area", [{}])[0]
    print(json.dumps({"ok": True, "temp": c[t], "feels": c[ft], "desc": c["weatherDesc"][0]["value"],
        "code": int(c["weatherCode"]), "humidity": c["humidity"], "wind": c[w], "windUnit": "mph" if imp else "km/h",
        "unit": "°F" if imp else "°C", "uv": c.get("uvIndex", ""), "vis": c.get("visibility", ""),
        "place": (area.get("areaName") or [{}])[0].get("value", ""), "days": days}))
except Exception:
    sys.exit(1)
' "$UNITS")
if [ -n "$OUT" ]; then printf '%s' "$OUT" > "$CACHE"; printf '%s' "$OUT"
elif [ -f "$CACHE" ]; then cat "$CACHE"
else echo '{"ok":false}'; fi
