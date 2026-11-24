"""Nautilus: "Open in Terminal" in the right-click menu (on a folder, or on the empty space of the
folder you are in). Opens the terminal chosen in Atelier's Settings -> Default apps
(behavior.terminal in ~/.config/atelier/settings.json; ghostty if unset) in that folder.

Needs the nautilus-python package. Linked by install.sh to
~/.local/share/nautilus-python/extensions/; restart Nautilus after a change: nautilus -q
"""
import json
import os
import shutil
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlparse

from gi.repository import GObject, Nautilus

SETTINGS = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "atelier/settings.json"

# how each terminal is told where to start (anything else just starts in that directory)
DIR_FLAG = {
    "ghostty": ["--working-directory={d}"],
    "kitty": ["--directory", "{d}"],
    "alacritty": ["--working-directory", "{d}"],
    "foot": ["--working-directory={d}"],
    "konsole": ["--workdir", "{d}"],
    "gnome-terminal": ["--working-directory={d}"],
    "kgx": ["--working-directory={d}"],
    "ptyxis": ["--new-window", "--working-directory={d}"],
    "wezterm": ["start", "--cwd", "{d}"],
    "xfce4-terminal": ["--working-directory={d}"],
}


def terminal():
    try:
        cmd = json.loads(SETTINGS.read_text()).get("behavior", {}).get("terminal") or "ghostty"
    except (OSError, ValueError):
        cmd = "ghostty"
    return cmd if shutil.which(cmd) else (shutil.which("ghostty") and "ghostty") or cmd


def local_path(info):
    uri = info.get_activation_uri() if hasattr(info, "get_activation_uri") else info.get_uri()
    u = urlparse(uri)
    return unquote(u.path) if u.scheme == "file" else None


def open_terminal(path):
    cmd = terminal()
    args = [a.format(d=path) for a in DIR_FLAG.get(os.path.basename(cmd), [])]
    subprocess.Popen([cmd, *args], cwd=path, start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class AtelierOpenTerminal(GObject.GObject, Nautilus.MenuProvider):
    def _item(self, name, path):
        item = Nautilus.MenuItem(name=name, label="Open in Terminal", tip="Open " + path + " in a terminal")
        item.connect("activate", lambda *_: open_terminal(path))
        return [item]

    def get_file_items(self, files):
        if len(files) != 1 or not files[0].is_directory():
            return []
        path = local_path(files[0])
        return self._item("AtelierOpenTerminal::Item", path) if path else []

    def get_background_items(self, folder):
        path = local_path(folder)
        return self._item("AtelierOpenTerminal::Background", path) if path else []
