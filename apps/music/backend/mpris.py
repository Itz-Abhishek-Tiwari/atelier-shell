"""MPRIS for Atelier Music: the desktop sees "Atelier Music" with title, artist, cover and full
controls (the shell's Music drawer, media keys, lock screen, playerctl).

Runs dbus-python on a GLib main loop in its own thread. D-Bus calls are handed to the daemon's
asyncio loop; property updates from the daemon are emitted on the GLib thread (GLib.idle_add).
If dbus-python / PyGObject are missing the daemon simply runs without MPRIS.
"""
import asyncio, os, subprocess, threading

try:
    import dbus, dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    AVAILABLE = True
except ImportError:            # pragma: no cover
    AVAILABLE = False

BUS_NAME = "org.mpris.MediaPlayer2.atelier_music"
PATH = "/org/mpris/MediaPlayer2"
ROOT = "org.mpris.MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"
PROPS = "org.freedesktop.DBus.Properties"
LAUNCHER = os.path.expanduser("~/.local/bin/atelier-music")

if AVAILABLE:
    class _Obj(dbus.service.Object):
        def __init__(self, bridge, bus):
            super().__init__(bus, PATH)
            self.b = bridge

        # ── org.freedesktop.DBus.Properties ──
        @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
        def Get(self, iface, prop):
            return self.GetAll(iface)[prop]

        @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
        def GetAll(self, iface):
            return self.b.props(iface)

        @dbus.service.method(PROPS, in_signature="ssv")
        def Set(self, iface, prop, value):
            self.b.call("set", prop, value)

        @dbus.service.signal(PROPS, signature="sa{sv}as")
        def PropertiesChanged(self, iface, changed, invalidated):
            pass

        # ── org.mpris.MediaPlayer2 ──
        @dbus.service.method(ROOT)
        def Raise(self):
            subprocess.Popen([LAUNCHER], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

        @dbus.service.method(ROOT)
        def Quit(self):
            pass

        # ── org.mpris.MediaPlayer2.Player ──
        @dbus.service.method(PLAYER)
        def Next(self): self.b.call("next")

        @dbus.service.method(PLAYER)
        def Previous(self): self.b.call("prev")

        @dbus.service.method(PLAYER)
        def Pause(self): self.b.call("pause")

        @dbus.service.method(PLAYER)
        def Play(self): self.b.call("play")

        @dbus.service.method(PLAYER)
        def PlayPause(self): self.b.call("toggle")

        @dbus.service.method(PLAYER)
        def Stop(self): self.b.call("pause")

        @dbus.service.method(PLAYER, in_signature="x")
        def Seek(self, offset): self.b.call("seek_rel", offset / 1e6)

        @dbus.service.method(PLAYER, in_signature="ox")
        def SetPosition(self, track, pos): self.b.call("seek", pos / 1e6)

        @dbus.service.method(PLAYER, in_signature="s")
        def OpenUri(self, uri): pass

        @dbus.service.signal(PLAYER, signature="x")
        def Seeked(self, pos):
            pass


class Mpris:
    """Bridge between the asyncio daemon and D-Bus.

    state()  → dict with keys playing, paused, current, pos, dur, shuffle, loop, volume, can_next, can_prev
    handler(cmd, *args) is a coroutine function run on the daemon's loop.
    """

    def __init__(self, loop, state, handler):
        self.loop, self.state, self.handler = loop, state, handler
        self.obj = None
        self.last = {}
        if not AVAILABLE:
            return
        threading.Thread(target=self._run, name="mpris", daemon=True).start()

    def _run(self):
        DBusGMainLoop(set_as_default=True)
        try:
            bus = dbus.SessionBus()
            self._name = dbus.service.BusName(BUS_NAME, bus, do_not_queue=True)
            self.obj = _Obj(self, bus)
        except Exception:
            self.obj = None
            return
        GLib.MainLoop().run()

    # D-Bus thread → daemon
    def call(self, cmd, *args):
        asyncio.run_coroutine_threadsafe(self.handler(cmd, *args), self.loop)

    def props(self, iface):
        s = self.state()
        if iface == ROOT:
            return dbus.Dictionary({
                "Identity": "Atelier Music", "DesktopEntry": "atelier-music",
                "CanQuit": False, "CanRaise": True, "CanSetFullscreen": False, "Fullscreen": False,
                "HasTrackList": False,
                "SupportedUriSchemes": dbus.Array([], signature="s"),
                "SupportedMimeTypes": dbus.Array([], signature="s"),
            }, signature="sv")
        has = s["current"] is not None
        return dbus.Dictionary({
            "PlaybackStatus": "Playing" if s["playing"] else ("Paused" if has else "Stopped"),
            "LoopStatus": {"none": "None", "track": "Track", "queue": "Playlist"}[s["loop"]],
            "Shuffle": dbus.Boolean(s["shuffle"]),
            "Rate": 1.0, "MinimumRate": 1.0, "MaximumRate": 1.0,
            "Volume": float(s["volume"]) / 100,
            "Metadata": self._meta(s),
            "Position": dbus.Int64(int(s["pos"] * 1e6)),
            "CanGoNext": dbus.Boolean(s["can_next"]), "CanGoPrevious": dbus.Boolean(has),
            "CanPlay": dbus.Boolean(has), "CanPause": dbus.Boolean(has),
            "CanSeek": dbus.Boolean(has and s["dur"] > 0), "CanControl": True,
        }, signature="sv")

    def _meta(self, s):
        t = s["current"]
        if not t:
            return dbus.Dictionary({"mpris:trackid": dbus.ObjectPath("/org/mpris/MediaPlayer2/TrackList/NoTrack")}, signature="sv")
        tid = "".join(c if c.isalnum() else "_" for c in t["id"])
        m = {
            "mpris:trackid": dbus.ObjectPath(f"/org/atelier/music/track/{tid}"),
            "xesam:title": t.get("title") or t["id"],
            "xesam:artist": dbus.Array([t.get("artist") or ""], signature="s"),
            "xesam:url": "https://music.youtube.com/watch?v=" + t["id"],
        }
        if s["dur"] > 0:
            m["mpris:length"] = dbus.Int64(int(s["dur"] * 1e6))
        art = s.get("art") or t.get("art") or t.get("thumb")
        if art:
            m["mpris:artUrl"] = art
        return dbus.Dictionary(m, signature="sv")

    # daemon → D-Bus: emit what changed (cheap to call often)
    def update(self, seeked=None):
        if not self.obj:
            return
        GLib.idle_add(self._emit, seeked)

    def _emit(self, seeked):
        if not self.obj:
            return False
        now = dict(self.props(PLAYER))
        now.pop("Position", None)
        changed = {k: v for k, v in now.items() if self.last.get(k) != v}
        self.last = now
        if changed:
            self.obj.PropertiesChanged(PLAYER, dbus.Dictionary(changed, signature="sv"), dbus.Array([], signature="s"))
        if seeked is not None:
            self.obj.Seeked(dbus.Int64(int(seeked * 1e6)))
        return False
