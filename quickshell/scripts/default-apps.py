#!/usr/bin/env python3
"""Default apps (Settings → Default apps): which app opens links, folders, text, pictures, ...

    default-apps.py list                     JSON: [{id, label, mimes, current, mixed, apps:[{id,name,icon}]}]
    default-apps.py set <category> <app.desktop>
                                             make <app> the default for every type of <category> it
                                             supports (writes ~/.config/mimeapps.list)
    default-apps.py terminal                 print the chosen terminal's command
    default-apps.py open terminal|files      start the chosen terminal / file manager (Super+T, Super+E)

Writes the freedesktop "[Default Applications]" of ~/.config/mimeapps.list, which xdg-open,
GTK/GIO, Qt/KDE and Electron apps all read. The terminal lives in Atelier's settings.json
(behavior.terminal, used by Super+T and the launcher; the Settings app writes it, `set terminal`
prints the command for it) and in ~/.config/xdg-terminals.list (xdg-terminal-exec: GIO uses it
for "Terminal=true" apps).

After a change the repo's seed copy (seed/config/mimeapps.list) is updated too, so a fresh
install of this folder gets the same defaults.
"""
import json
import os
import shutil
import sys
from pathlib import Path

HOME = Path.home()
CONF = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
DATA_HOME = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share")
DATA_DIRS = [Path(p) for p in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if p]
MIMEAPPS = CONF / "mimeapps.list"
SETTINGS = CONF / "atelier/settings.json"
# quickshell/scripts/ -> repo root (the config folder is a symlink into the repo)
REPO = Path(os.path.realpath(__file__)).parent.parent.parent
SEED = REPO / "seed/config/mimeapps.list"

CATEGORIES = [
    ("browser", "Web browser", ["x-scheme-handler/https", "x-scheme-handler/http", "text/html",
                                "application/xhtml+xml", "x-scheme-handler/about", "x-scheme-handler/unknown"]),
    ("mail", "Email", ["x-scheme-handler/mailto"]),
    ("files", "Files", ["inode/directory"]),
    ("text", "Text editor", ["text/plain", "text/markdown", "text/x-python", "text/x-python3", "application/json",
                             "application/x-shellscript", "text/x-shellscript", "text/x-csrc", "text/x-c++src",
                             "text/x-chdr", "text/css", "text/javascript", "application/javascript",
                             "application/x-yaml", "application/toml", "text/x-lua", "application/xml",
                             "text/x-log", "text/csv"]),
    ("image", "Pictures", ["image/png", "image/jpeg", "image/webp", "image/gif", "image/bmp", "image/tiff",
                           "image/avif", "image/heic", "image/svg+xml", "image/x-icon"]),
    ("video", "Videos", ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo",
                         "video/mpeg", "video/ogg", "video/3gpp", "video/x-flv"]),
    ("audio", "Music", ["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-wav", "audio/wav", "audio/mp4",
                        "audio/aac", "audio/opus", "audio/x-m4a", "audio/x-flac", "audio/webm"]),
    ("pdf", "PDF & books", ["application/pdf", "application/epub+zip", "image/vnd.djvu"]),
    ("archive", "Archives", ["application/zip", "application/x-tar", "application/x-compressed-tar",
                             "application/x-xz-compressed-tar", "application/x-zstd-compressed-tar",
                             "application/x-bzip2-compressed-tar", "application/gzip", "application/x-7z-compressed",
                             "application/vnd.rar", "application/x-rar", "application/zstd"]),
    ("document", "Documents", ["application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                               "application/msword", "application/vnd.oasis.opendocument.text", "application/rtf",
                               "text/rtf", "application/vnd.openxmlformats-officedocument.wordprocessingml.template",
                               "application/vnd.oasis.opendocument.text-template"]),
    ("sheet", "Spreadsheets", ["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                               "application/vnd.ms-excel", "application/vnd.oasis.opendocument.spreadsheet",
                               "application/vnd.openxmlformats-officedocument.spreadsheetml.template"]),
    ("slides", "Presentations", ["application/vnd.openxmlformats-officedocument.presentationml.presentation",
                                 "application/vnd.ms-powerpoint", "application/vnd.oasis.opendocument.presentation",
                                 "application/vnd.openxmlformats-officedocument.presentationml.slideshow"]),
]


# freedesktop Categories that also qualify an app (it opens every type of the category)
KIND = {"browser": "WebBrowser", "mail": "Email", "files": "FileManager", "text": "TextEditor"}
NO_BROWSERS = {"text", "video", "audio", "archive", "files", "document", "sheet", "slides"}


# ---- desktop entries ------------------------------------------------------------
def app_dirs():
    return [DATA_HOME / "applications"] + [d / "applications" for d in DATA_DIRS]


def parse_entry(path):
    out, section = {}, None
    try:
        for line in path.read_text(errors="replace").splitlines():
            line = line.strip()
            if line.startswith("["):
                section = line
                continue
            if section != "[Desktop Entry]" or "=" not in line or line.startswith("#"):
                continue
            k, v = line.split("=", 1)
            out.setdefault(k.strip(), v.strip())
    except OSError:
        return None
    return out


def entries():
    """desktop id -> entry; earlier dirs win (user's ~/.local/share first)."""
    found = {}
    for base in app_dirs():
        if not base.is_dir():
            continue
        for p in base.rglob("*.desktop"):
            did = str(p.relative_to(base)).replace("/", "-")
            if did in found:
                continue
            e = parse_entry(p)
            if not e or e.get("Type", "Application") != "Application":
                continue
            found[did] = e
    return found


def usable(e):
    if e.get("Hidden", "").lower() == "true":
        return False
    te = e.get("TryExec")
    if te and not (shutil.which(te) or os.access(te, os.X_OK)):
        return False
    return True


def mimes_of(e):
    return [m for m in e.get("MimeType", "").split(";") if m]


def exec_cmd(e):
    """First word of Exec (the binary), without field codes."""
    parts = [p for p in e.get("Exec", "").split() if not p.startswith("%")]
    while parts and (parts[0] == "env" or "=" in parts[0]):
        parts.pop(0)
    return parts[0] if parts else ""


# ---- mimeapps.list --------------------------------------------------------------
def mimeapps_chain():
    desktops = [d.lower() for d in (os.environ.get("XDG_CURRENT_DESKTOP") or "").split(":") if d]
    conf_dirs = [CONF] + [Path(p) for p in (os.environ.get("XDG_CONFIG_DIRS") or "/etc/xdg").split(":") if p]
    files = []
    for d in conf_dirs:
        files += [d / f"{de}-mimeapps.list" for de in desktops] + [d / "mimeapps.list"]
    for d in [DATA_HOME] + DATA_DIRS:
        files += [d / "applications" / f"{de}-mimeapps.list" for de in desktops] + [d / "applications/mimeapps.list"]
    return files


def read_defaults(path):
    out, section = {}, None
    try:
        for line in path.read_text(errors="replace").splitlines():
            s = line.strip()
            if s.startswith("["):
                section = s
            elif section == "[Default Applications]" and "=" in s and not s.startswith("#"):
                k, v = s.split("=", 1)
                out.setdefault(k.strip(), [a for a in v.strip().split(";") if a])
    except OSError:
        pass
    return out


def default_for(mime, chain, apps):
    for defaults in chain:
        for a in defaults.get(mime, []):
            if a in apps and usable(apps[a]):
                return a
    # no explicit default: what xdg-mime would fall back to (mimeinfo.cache order)
    for base in app_dirs():
        cache = base / "mimeinfo.cache"
        for a in read_cache(cache).get(mime, []):
            if a in apps and usable(apps[a]):
                return a
    return ""


_cache = {}
def read_cache(path):
    if path not in _cache:
        out, section = {}, None
        try:
            for line in path.read_text(errors="replace").splitlines():
                s = line.strip()
                if s.startswith("["):
                    section = s
                elif section == "[MIME Cache]" and "=" in s:
                    k, v = s.split("=", 1)
                    out[k] = [a for a in v.split(";") if a]
        except OSError:
            pass
        _cache[path] = out
    return _cache[path]


def write_defaults(updates):
    """Set keys in [Default Applications] of ~/.config/mimeapps.list, keep everything else."""
    lines = MIMEAPPS.read_text().splitlines() if MIMEAPPS.exists() else []
    out, section, done, seen_section = [], None, set(), False

    def flush_missing():
        tail = []
        while out and not out[-1].strip():
            tail.append(out.pop())
        for k, v in updates.items():
            if k not in done:
                out.append(f"{k}={v};")
                done.add(k)
        out.extend(tail)

    for line in lines:
        s = line.strip()
        if s.startswith("["):
            if section == "[Default Applications]":
                flush_missing()
            section = s
            if s == "[Default Applications]":
                seen_section = True
        elif section == "[Default Applications]" and "=" in s:
            k = s.split("=", 1)[0].strip()
            if k in updates:
                if k not in done:
                    out.append(f"{k}={updates[k]};")
                    done.add(k)
                continue
        out.append(line)
    if section == "[Default Applications]":
        flush_missing()
    if not seen_section:
        if out and out[-1].strip():
            out.append("")
        out.append("[Default Applications]")
        flush_missing()
    text = "\n".join(out).rstrip("\n") + "\n"
    MIMEAPPS.parent.mkdir(parents=True, exist_ok=True)
    tmp = MIMEAPPS.with_name(MIMEAPPS.name + ".atelier-tmp")
    tmp.write_text(text)
    tmp.replace(MIMEAPPS)
    if SEED.parent.is_dir() and CONF == HOME / ".config":
        try:
            shutil.copyfile(MIMEAPPS, SEED)
        except OSError:
            pass


# ---- terminal --------------------------------------------------------------------
def terminals(apps):
    return {k: e for k, e in apps.items()
            if "TerminalEmulator" in e.get("Categories", "").split(";") and usable(e)
            and e.get("NoDisplay", "").lower() != "true"}


def current_terminal():
    try:
        return json.loads(SETTINGS.read_text()).get("behavior", {}).get("terminal") or "ghostty"
    except (OSError, ValueError):
        return "ghostty"


def set_terminal(did, e):
    """xdg-terminals.list only; prints the command for Settings.behavior.terminal (the shell owns
    settings.json; writing it here would race the Settings app's own save)."""
    (CONF / "xdg-terminals.list").write_text(did + "\n")
    print(exec_cmd(e))


# ---- commands --------------------------------------------------------------------
def app_info(did, e):
    return {"id": did, "name": e.get("Name", did.removesuffix(".desktop")), "icon": e.get("Icon", "")}


def cats(e):
    return set(e.get("Categories", "").split(";"))


def hidden(e):
    return e.get("NoDisplay", "").lower() == "true"


def handles(cid, e, mset):
    """Can this entry open the category? By declared types, or by its freedesktop category
    (VS Code lists no text types; it is still a TextEditor)."""
    if cid in NO_BROWSERS and "WebBrowser" in cats(e):
        return False
    return bool(mset & set(mimes_of(e))) or bool(KIND.get(cid) and KIND[cid] in cats(e))


def candidates(cid, mimes, apps, cur):
    """One choice per app. Some apps ship a hidden helper launcher that declares the types
    (zathura-pdf-mupdf, com.google.Chrome) next to the visible one: merged by Name, the
    entry that declares the types is the one written to mimeapps.list."""
    mset = set(mimes)
    visible_names = {e.get("Name") for e in apps.values() if usable(e) and not hidden(e)}
    groups = {}
    for k, e in apps.items():
        if usable(e) and handles(cid, e, mset) and e.get("Name") in visible_names:
            groups.setdefault(e.get("Name"), []).append((k, e))
    out = []
    for name, members in groups.items():
        ids = [k for k, _ in members]
        pick = (cur if cur in ids else None) \
            or next((k for k, e in members if not hidden(e) and mset & set(mimes_of(e))), None) \
            or next((k for k, e in members if mset & set(mimes_of(e))), None) or ids[0]
        icon = next((e.get("Icon") for k, e in members if e.get("Icon")), "") or \
            next((e.get("Icon", "") for e in apps.values() if e.get("Name") == name and e.get("Icon")), "")
        out.append({"id": pick, "name": name, "icon": icon})
    if cur and cur not in {a["id"] for a in out} and cur in apps:
        out.append(app_info(cur, apps[cur]))
    return sorted(out, key=lambda a: a["name"].lower())


def cmd_list():
    apps = entries()
    chain = [read_defaults(p) for p in mimeapps_chain()]
    result = []
    for cid, label, mimes in CATEGORIES:
        cur = default_for(mimes[0], chain, apps)
        others = {default_for(m, chain, apps) for m in mimes[1:]} - {""}
        result.append({"id": cid, "label": label, "current": cur,
                       "currentName": apps[cur].get("Name", cur) if cur else "",
                       "mixed": bool(others - {cur}),
                       "apps": candidates(cid, mimes, apps, cur)})
    terms = terminals(apps)
    tcmd = current_terminal()
    tcur = next((k for k, e in terms.items() if exec_cmd(e) == tcmd), "")
    result.append({"id": "terminal", "label": "Terminal", "current": tcur,
                   "currentName": terms[tcur].get("Name", tcur) if tcur else tcmd, "mixed": False,
                   "apps": sorted((app_info(k, e) for k, e in terms.items()), key=lambda a: a["name"].lower())})
    print(json.dumps(result))


def cmd_set(cid, did):
    apps = entries()
    if did not in apps:
        sys.exit(f"unknown app: {did}")
    e = apps[did]
    if cid == "terminal":
        set_terminal(did, e)
        return
    cat = next((c for c in CATEGORIES if c[0] == cid), None)
    if not cat:
        sys.exit(f"unknown category: {cid}")
    supported = set(mimes_of(e))
    if KIND.get(cid) and KIND[cid] in cats(e):
        mimes = list(cat[2])   # a real browser / editor / file manager takes the whole category
    else:
        mimes = [m for m in cat[2] if m in supported] or [cat[2][0]]
    write_defaults({m: did for m in mimes})


def main():
    a = sys.argv[1:]
    if a[:1] == ["list"]:
        cmd_list()
    elif a[:1] == ["set"] and len(a) == 3:
        cmd_set(a[1], a[2])
    elif a[:1] == ["terminal"]:
        print(current_terminal())
    elif a[:1] == ["open"] and len(a) == 2 and a[1] in ("terminal", "files"):
        if a[1] == "terminal":
            cmd = current_terminal()
            os.execvp(cmd, [cmd])
        os.execvp("xdg-open", ["xdg-open", str(HOME)])
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
