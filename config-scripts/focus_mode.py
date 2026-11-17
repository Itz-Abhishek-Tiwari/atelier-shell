#!/usr/bin/env python3
"""Focus mode toggle (Super+Shift+F): opaque, undimmed windows on a calm wallpaper.

    focus_mode.py            toggle
    focus_mode.py on|off     set explicitly
    focus_mode.py status     prints on|off

Applied live with `hyprctl eval` (Hyprland's Lua config has no `hyprctl keyword`, and a reload
would make the cursor hitch). Turning it off restores the Settings-app values from
~/.config/hypr/atelier-settings.lua and the wallpaper that was set before.
Note: with a wallpaper-* theme active, the wallpaper swap also re-themes the desktop.
"""
import json
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
STATE = HOME / ".cache/atelier/focus_mode.json"
WALL_FILE = HOME / ".cache/current_wallpaper"
FOCUS_WALL = HOME / ".config/hypr/wall/08.png"   # calm wallpaper while focusing (skipped if missing)

ON_LUA = "hl.config({ decoration = { active_opacity = 1.0, inactive_opacity = 1.0, dim_inactive = false } })"
OFF_LUA = ('local w = dofile(os.getenv("HOME") .. "/.config/hypr/atelier-mode.lua").settings(); '
           "hl.config({ decoration = { active_opacity = w.active_opacity, "
           "inactive_opacity = w.inactive_opacity, dim_inactive = true } })")


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=10)


def notify(title, body, icon):
    subprocess.run(["notify-send", "-a", "Focus mode", "-i", icon, title, body])


def set_wallpaper(path):
    if path and Path(path).is_file():
        run("qs", "ipc", "call", "wallpaper", "set", str(path))


def current_wallpaper():
    try:
        return WALL_FILE.read_text().strip().splitlines()[0]
    except (OSError, IndexError):
        return ""


def turn_on():
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps({"wallpaper": current_wallpaper()}))
    r = run("hyprctl", "eval", ON_LUA)
    set_wallpaper(FOCUS_WALL)
    notify("Focus mode", "On: opaque windows, no dimming", "dialog-information")
    return r.returncode


def turn_off():
    try:
        prev = json.loads(STATE.read_text()).get("wallpaper", "")
    except (OSError, ValueError):
        prev = ""
    STATE.unlink(missing_ok=True)
    r = run("hyprctl", "eval", OFF_LUA)
    set_wallpaper(prev)
    notify("Focus mode", "Off: back to your settings", "weather-clear")
    return r.returncode


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "toggle"
    on = STATE.exists()
    if arg == "status":
        print("on" if on else "off")
        return 0
    if arg == "on" or (arg == "toggle" and not on):
        return turn_on()
    if arg == "off" or (arg == "toggle" and on):
        return turn_off()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
