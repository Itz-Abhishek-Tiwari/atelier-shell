#!/usr/bin/env python3
"""Package data for Settings → Install & remove (pacman + AUR through yay or paru).

    packages.py search <words>   JSON: repo matches (pacman -Ss, instant), best first
    packages.py aur <words>      JSON: AUR matches (the AUR web API, the same query yay sends)
    packages.py info <names>     JSON: those repo packages, in the order given (pacman -Si; unknown names skipped)
    packages.py installed        JSON: packages you installed on purpose (pacman -Qe), with the
                                 app name/icon of their .desktop entry, size, date, AUR flag
    packages.py helper           the AUR helper in use ("yay", "paru" or "")

Read-only: installing and removing run in a terminal from the page (sudo asks there), so the
user sees the password prompt and the build output.
"""
import glob
import urllib.parse
import urllib.request
import json
import re
import shutil
import subprocess
import sys

# never offered for removal: removing these breaks booting, logging in or this desktop
PROTECTED = {
    "base", "base-devel", "linux", "linux-lts", "linux-zen", "linux-hardened", "linux-firmware",
    "systemd", "glibc", "pacman", "sudo", "bash", "zsh", "coreutils", "filesystem", "grub",
    "efibootmgr", "mkinitcpio", "networkmanager", "pipewire", "wireplumber", "hyprland",
    "quickshell", "qt6-base", "qt6-declarative", "mesa", "greetd", "yay", "yay-bin", "paru", "paru-bin",
}


def run(*cmd, timeout=60):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ""


def helper():
    for h in ("yay", "paru"):
        if shutil.which(h):
            return h
    return ""


def _rank(res, words):
    q = " ".join(words).lower()

    def rank(p):
        n = p["name"].lower()
        return (n != q, not n.startswith(words[0].lower()), -p["votes"], len(n))
    res.sort(key=rank)
    return res[:60]


def search(words):
    """Repo packages (pacman -Ss: local sync databases, no network)."""
    words = [w for w in words if w.strip()]
    if not words:
        return []
    out = run("pacman", "-Ss", *words, timeout=20)
    res, cur = [], None
    for line in out.splitlines():
        m = re.match(r"^(\S+)/(\S+)\s+(\S+)(.*)$", line)
        if m:
            repo, name, ver, rest = m.groups()
            cur = {"name": name, "repo": repo, "version": ver, "desc": "", "aur": False,
                   "installed": "installed" in rest.lower(), "votes": 0, "protected": name in PROTECTED}
            res.append(cur)
        elif cur is not None and line.startswith(" "):
            cur["desc"] = (cur["desc"] + " " + line.strip()).strip()
    return _rank(res, words)


def info(names):
    """Repo packages by exact name, in the order asked (the drawer's "popular" list)."""
    names = [n for n in names if re.match(r"^[a-z0-9@._+-]+$", n)]
    if not names:
        return []
    have = set(run("pacman", "-Qq").split())
    found = {}
    for block in run("pacman", "-Si", *names, timeout=30).split("\n\n"):
        f = {}
        for line in block.splitlines():
            m = re.match(r"^([A-Za-z ]+?)\s*:\s(.*)$", line)
            if m:
                f[m.group(1)] = m.group(2).strip()
        n = f.get("Name")
        if n:
            found[n] = {"name": n, "repo": f.get("Repository", ""), "version": f.get("Version", ""),
                        "desc": f.get("Description", ""), "aur": False, "installed": n in have,
                        "votes": 0, "protected": n in PROTECTED}
    return [found[n] for n in names if n in found]


def aur(words):
    """AUR packages from aur.archlinux.org/rpc (name + description search on the longest word,
    then every word must match), skipping ones flagged out of date."""
    words = [w for w in words if w.strip()]
    if not words:
        return []
    key = max(words, key=len)
    url = "https://aur.archlinux.org/rpc/v5/search/" + urllib.parse.quote(key) + "?by=name-desc"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "atelier-settings"})
        data = json.load(urllib.request.urlopen(req, timeout=20)).get("results", [])
    except Exception:
        return []
    have = set(run("pacman", "-Qq").split())
    res = []
    for r in data:
        text = (r.get("Name", "") + " " + (r.get("Description") or "")).lower()
        if not all(w.lower() in text for w in words):
            continue
        res.append({"name": r["Name"], "repo": "aur", "version": r.get("Version", ""),
                    "desc": r.get("Description") or "", "aur": True, "installed": r["Name"] in have,
                    "votes": int(r.get("NumVotes") or 0), "outdated": bool(r.get("OutOfDate")),
                    "protected": r["Name"] in PROTECTED})
    return _rank(res, words)


def desktop_apps():
    """package -> {app, icon} from the .desktop files it owns (the visible apps)."""
    files = sorted(glob.glob("/usr/share/applications/*.desktop"))
    if not files:
        return {}
    owners = run("pacman", "-Qo", *files, timeout=60)
    by_file = {}
    for line in owners.splitlines():
        m = re.match(r"^(\S+) is owned by (\S+) ", line)
        if m:
            by_file[m.group(1)] = m.group(2)
    apps = {}
    for f, pkg in by_file.items():
        try:
            text = open(f, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        main = text.split("\n[", 1)[0]                       # [Desktop Entry] only, not actions
        if re.search(r"(?m)^NoDisplay\s*=\s*true", main) or re.search(r"(?m)^Hidden\s*=\s*true", main):
            continue
        name = (re.search(r"(?m)^Name\s*=\s*(.+)$", main) or [None, ""])[1].strip()
        icon = (re.search(r"(?m)^Icon\s*=\s*(.+)$", main) or [None, ""])[1].strip()
        if name and pkg not in apps:
            apps[pkg] = {"app": name, "icon": icon}
    return apps


def installed():
    explicit = run("pacman", "-Qeq").split()
    foreign = set(run("pacman", "-Qmq").split())
    info = run("pacman", "-Qi", *explicit, timeout=60) if explicit else ""
    apps = desktop_apps()
    out = []
    for block in info.split("\n\n"):
        f = {}
        for line in block.splitlines():
            m = re.match(r"^([A-Za-z ]+?)\s*:\s(.*)$", line)
            if m:
                f[m.group(1)] = m.group(2).strip()
        name = f.get("Name")
        if not name:
            continue
        a = apps.get(name, {})
        out.append({"name": name, "version": f.get("Version", ""), "desc": f.get("Description", ""),
                    "size": f.get("Installed Size", ""), "date": f.get("Install Date", ""),
                    "aur": name in foreign, "app": a.get("app", ""), "icon": a.get("icon", ""),
                    "protected": name in PROTECTED})
    out.sort(key=lambda p: (p["app"] or p["name"]).lower())
    return out


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "search":
        print(json.dumps(search(sys.argv[2:])))
    elif cmd == "aur":
        print(json.dumps(aur(sys.argv[2:])))
    elif cmd == "info":
        print(json.dumps(info(sys.argv[2:])))
    elif cmd == "installed":
        print(json.dumps(installed()))
    elif cmd == "helper":
        print(helper())
    else:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
