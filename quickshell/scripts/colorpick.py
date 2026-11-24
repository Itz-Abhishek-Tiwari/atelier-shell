#!/usr/bin/env python3
"""Pick a colour from anywhere on screen (slurp point + grim 1×1 pixel; no extra packages).
Prints "#rrggbb" on success, nothing when cancelled."""
import subprocess
import sys

p = subprocess.run(["slurp", "-p", "-b", "00000000", "-f", "%x,%y 1x1"], capture_output=True, text=True)
geo = p.stdout.strip()
if p.returncode != 0 or not geo:
    sys.exit(1)
g = subprocess.run(["grim", "-g", geo, "-t", "ppm", "-"], capture_output=True)
data = g.stdout
if g.returncode != 0 or not data.startswith(b"P6"):
    sys.exit(1)
rgb = data[-3:]
print("#%02x%02x%02x" % tuple(rgb))
