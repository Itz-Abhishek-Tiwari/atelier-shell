#!/usr/bin/env python3
"""Profile picture helper for Settings → Profile.

  avatar.py set <image>    centre-crops to a square, scales to 512 px and writes ~/.face (PNG)
                           (the previous picture is kept as ~/.cache/atelier/face-previous.png)
  avatar.py remove         moves ~/.face aside to the same backup path
  avatar.py info           JSON: login, real name (GECOS), host, whether ~/.face exists + its mtime

~/.face is the freedesktop per-user picture: the lock screens, the Settings sidebar and the
login screen (scripts/greeter-sync.sh) all read it. Prints one JSON line.
"""
import json
import os
import pwd
import shutil
import socket
import sys

HOME = os.path.expanduser("~")
FACE = os.path.join(HOME, ".face")
BACKUP = os.path.join(HOME, ".cache", "atelier", "face-previous.png")
SIZE = 512


def out(obj, code=0):
    print(json.dumps(obj), flush=True)
    sys.exit(code)


def backup():
    if os.path.isfile(FACE):
        os.makedirs(os.path.dirname(BACKUP), exist_ok=True)
        shutil.copyfile(FACE, BACKUP)


def set_face(src):
    from PIL import Image, ImageOps
    try:
        im = Image.open(src)
        im.seek(0)                      # first frame of a GIF/WebP animation
        im = ImageOps.exif_transpose(im)
    except Exception as e:
        out({"ok": False, "error": "can't open that image: %s" % e}, 1)
    im = im.convert("RGBA") if im.mode in ("RGBA", "LA", "P") else im.convert("RGB")
    side = min(im.size)
    left = (im.width - side) // 2
    # portraits: faces sit in the upper part, so crop a little above centre
    top = (im.height - side) // 3 if im.height > im.width else (im.height - side) // 2
    im = im.crop((left, top, left + side, top + side)).resize((SIZE, SIZE), Image.LANCZOS)
    backup()
    tmp = FACE + ".tmp"
    im.save(tmp, "PNG", optimize=True)
    os.replace(tmp, FACE)
    out({"ok": True, "face": FACE})


def remove():
    if os.path.isfile(FACE):
        backup()
        os.remove(FACE)
    out({"ok": True})


def info():
    pw = pwd.getpwuid(os.getuid())
    gecos = (pw.pw_gecos or "").split(",")[0].strip()
    st = os.stat(FACE) if os.path.isfile(FACE) else None
    out({"login": pw.pw_name, "realName": gecos, "host": socket.gethostname(),
         "hasFace": st is not None, "faceMtime": int(st.st_mtime) if st else 0,
         "hasBackup": os.path.isfile(BACKUP)})


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "set" and len(sys.argv) > 2:
        set_face(os.path.expanduser(sys.argv[2]))
    elif cmd == "remove":
        remove()
    elif cmd == "info":
        info()
    elif cmd == "restore":
        if not os.path.isfile(BACKUP):
            out({"ok": False, "error": "no previous picture"}, 1)
        shutil.copyfile(BACKUP, FACE)
        out({"ok": True})
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
