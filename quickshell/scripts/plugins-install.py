#!/usr/bin/env python3
"""Manage plugin folders in ~/.config/atelier/plugins.
  plugins-install.py install <git-url | .zip url | local folder | local .zip> [plugins dir]
  plugins-install.py remove  <id> [plugins dir]
  plugins-install.py trust   <id> [plugins dir]      (approve the plugin's current files and switch it on)
A freshly installed plugin is left switched off and not approved: the user reviews it in Settings → Plugins.
Prints one line, `ok: ...` or `error: ...`, and exits non-zero on error."""
import hashlib, json, os, re, shutil, subprocess, sys, tempfile, urllib.request, zipfile

args = sys.argv[1:]
if len(args) < 2 or args[0] not in ("install", "remove", "trust"):
    sys.exit(__doc__)
cmd, target = args[0], args[1]
root = args[2] if len(args) > 2 else os.path.expanduser("~/.config/atelier/plugins")
ID = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")


def fail(msg):
    print("error: " + msg)
    sys.exit(1)


def tree_hash(d):    # same as plugins-scan.py
    h = hashlib.sha256()
    for base, dirs, files in os.walk(d):
        dirs[:] = sorted(x for x in dirs if x != ".git")
        for f in sorted(files):
            if f in (".disabled", ".trusted") and base == d:
                continue
            p = os.path.join(base, f)
            h.update(os.path.relpath(p, d).encode() + b"\0")
            h.update(open(p, "rb").read())
    return h.hexdigest()


def plugin_dir(pid):
    if not ID.match(pid):
        fail("bad plugin id")
    d = os.path.join(root, pid)
    if not os.path.isfile(os.path.join(d, "plugin.json")):
        fail("no such plugin: " + pid)
    return d


def find_manifest_dir(top):
    if os.path.isfile(os.path.join(top, "plugin.json")):
        return top
    subs = [os.path.join(top, x) for x in os.listdir(top) if os.path.isdir(os.path.join(top, x)) and not x.startswith(".")]
    if len(subs) == 1 and os.path.isfile(os.path.join(subs[0], "plugin.json")):
        return subs[0]
    fail("no plugin.json found at the top of that source")


def safe_extract(z, dest):
    base = os.path.realpath(dest) + os.sep
    for n in z.namelist():
        if not os.path.realpath(os.path.join(dest, n)).startswith(base):
            fail("zip tries to write outside its folder")
    z.extractall(dest)


if cmd == "remove":
    shutil.rmtree(plugin_dir(target))
    print("ok: removed " + target)

elif cmd == "trust":
    d = plugin_dir(target)
    open(os.path.join(d, ".trusted"), "w").write(tree_hash(d))
    try:
        os.remove(os.path.join(d, ".disabled"))
    except OSError:
        pass
    print("ok: approved " + target)

else:
    tmp = tempfile.mkdtemp(prefix="atelier-plugin-")
    try:
        src = os.path.join(tmp, "src")
        if re.match(r"^https?://.+\.zip(\?.*)?$", target):
            zf = os.path.join(tmp, "p.zip")
            urllib.request.urlretrieve(target, zf)
            safe_extract(zipfile.ZipFile(zf), src)
        elif re.match(r"^(https?://|git@|ssh://|git://)", target) or target.endswith(".git"):
            r = subprocess.run(["git", "clone", "--depth", "1", "--", target, src], capture_output=True, text=True, timeout=120)
            if r.returncode:
                fail("git clone failed: " + r.stderr.strip().splitlines()[-1] if r.stderr.strip() else "git clone failed")
            shutil.rmtree(os.path.join(src, ".git"), ignore_errors=True)
        elif os.path.isdir(os.path.expanduser(target)):
            shutil.copytree(os.path.expanduser(target), src, ignore=shutil.ignore_patterns(".git"))
        elif os.path.isfile(os.path.expanduser(target)) and target.endswith(".zip"):
            safe_extract(zipfile.ZipFile(os.path.expanduser(target)), src)
        else:
            fail("not a git URL, .zip or folder: " + target)
        pdir = find_manifest_dir(src)
        try:
            json.load(open(os.path.join(pdir, "plugin.json")))
        except Exception as e:
            fail("plugin.json is not valid JSON: " + str(e))
        pid = re.sub(r"[^a-z0-9._-]+", "-", os.path.basename(target.rstrip("/")).removesuffix(".git").removesuffix(".zip").lower()).strip("-.")
        if pdir != src:
            pid = re.sub(r"[^a-z0-9._-]+", "-", os.path.basename(pdir).lower()).strip("-.")
        if not ID.match(pid):
            fail("cannot derive a plugin id from " + target)
        dest = os.path.join(root, pid)
        if os.path.exists(dest):
            fail("a plugin called '" + pid + "' is already installed (remove it first)")
        os.makedirs(root, exist_ok=True)
        shutil.copytree(pdir, dest, symlinks=False)
        open(os.path.join(dest, ".disabled"), "w").close()
        print("ok: installed " + pid + " (review and switch it on in Settings → Plugins)")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
