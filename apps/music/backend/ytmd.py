#!/usr/bin/env python3
"""ytmd: the backend of Atelier Music (apps/music). Python stdlib (+ dbus-python for MPRIS).

  ytmd.py --daemon        run the daemon (the app starts it; it exits ~10 min after the last
                          window closes with nothing playing)
  ytmd.py <cmd> [args…]   send one command and print the JSON reply, e.g.
                          search "daft punk" · home · foryou · radio <videoId> · play <videoId>
                          toggle · next · prev · status · download <videoId> · offline · usage

Modules: innertube.py (YouTube Music API + stream URLs), library.py (history, offline files,
"For you"), mpris.py (the desktop's media controls).

Playback order for a track: a downloaded copy → a cached copy → a direct stream URL (~0.2 s to
resolve, and the file is cached while it plays) → yt-dlp (live streams, region locks).
Offline, tracks without a local copy are skipped.

Socket: $XDG_RUNTIME_DIR/atelier-music.sock, newline-delimited JSON.
  → {"id": 1, "cmd": "search", "args": ["query"]}
  ← {"id": 1, "result": …}          a reply
  ← {"event": "status", …}           playback / queue changed (to every client)
  ← {"event": "files", "files": {id: "download"|"cache"}, "progress": {id: 0..1}}
"""
import asyncio, json, logging, os, random, socket, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import innertube as yt          # noqa: E402
from library import Library     # noqa: E402
import mpris                    # noqa: E402

RUN = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
SOCK = os.path.join(RUN, "atelier-music.sock")
MPV_SOCK = os.path.join(RUN, "atelier-music-mpv.sock")
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "atelier-music")
STATE_FILE = os.path.join(STATE_DIR, "queue.json")
IDLE_EXIT = 600
LOG_FILE = os.path.join(STATE_DIR, "ytmd.log")
log = logging.getLogger("ytmd")
RADIO_TTL = 6 * 3600
FORYOU_TTL = 3600


def mpv_str(s):
    """mpv per-file option value that may contain commas: %<bytes>%value."""
    return f"%{len(s.encode())}%{s}"


class Daemon:
    def __init__(self):
        self.api = yt.InnerTube()      # search / home / radio
        self.res = yt.InnerTube()      # stream URLs (own connection: a search never waits on a resolve)
        self.dl = yt.InnerTube()       # resolves for background caching / downloads
        self.lib = Library()
        self.queue, self.index = [], -1
        self.autoplay, self.shuffle, self.loop_mode, self.volume = True, False, "none", 100
        self.paused = False
        self.pos, self.dur, self.pos_at = 0.0, 0.0, time.time()
        self.loaded = self.loading = False
        self.via = ""                  # "download" | "cache" | "stream" | "yt-dlp"
        self.online = True
        self.notice = ""               # one-line message for the UI (offline skips, failures)
        self.cache = {}                # videoId → (url, ua, expires_at)
        self.radios = {}               # seed → (fetched_at, tracks)
        self.foryou = (0, 0, [])       # (computed_at, history_count, tracks)
        self.progress = {}             # videoId → 0..1 while caching / downloading
        self.want_download = set()
        self.jobs = None               # asyncio.Queue of (track, download?)
        self.clients = set()
        self.mpv = self.mw = None
        self.last_active = time.time()
        self.radio_for = ""
        self.mpris = None
        self.sleep_at = 0.0            # epoch seconds; 0 = off
        self.sleep_end_track = False   # pause when the current song ends
        self.sleep_task = None
        try:
            with open(STATE_FILE) as f:
                d = json.load(f)
            self.queue, self.index = d.get("queue", []), d.get("index", -1)
            self.autoplay = d.get("autoplay", True)
            self.shuffle = d.get("shuffle", False)
            self.loop_mode = d.get("loop", "none")
            self.volume = d.get("volume", 100)
        except (OSError, ValueError):
            pass

    async def run_sync(self, fn, *a):
        return await asyncio.get_running_loop().run_in_executor(None, fn, *a)

    def save(self):
        try:
            os.makedirs(STATE_DIR, exist_ok=True)
            with open(STATE_FILE, "w") as f:
                json.dump({"queue": self.queue[-300:], "index": self.index, "autoplay": self.autoplay,
                           "shuffle": self.shuffle, "loop": self.loop_mode, "volume": self.volume}, f)
        except OSError:
            pass

    # ═══════════════════ status ═══════════════════
    def cur(self):
        return self.queue[self.index] if 0 <= self.index < len(self.queue) else None

    def live_pos(self):
        if self.loaded and not self.paused and not self.loading:
            return min(self.dur or 1e9, self.pos + time.time() - self.pos_at)
        return self.pos

    def status(self):
        cur = self.cur()
        art = None
        if cur:
            la = self.lib.local_art(cur["id"])
            art = "file://" + la if la else None
        return {"event": "status", "current": cur, "index": self.index, "queue": self.queue,
                "playing": bool(cur and self.loaded and not self.paused), "paused": self.paused,
                "loading": self.loading, "pos": round(self.live_pos(), 2), "dur": self.dur,
                "autoplay": self.autoplay, "shuffle": self.shuffle, "loop": self.loop_mode, "volume": self.volume,
                "via": self.via, "online": self.online, "notice": self.notice, "art": art,
                "liked": bool(cur and cur["id"] in self.likes),
                "sleepAt": self.sleep_at, "sleepEndOfTrack": self.sleep_end_track}

    def mpris_state(self):
        s = self.status()
        s["can_next"] = self.index + 1 < len(self.queue) or self.autoplay
        return s

    def send_all(self, msg):
        line = (json.dumps(msg) + "\n").encode()
        for w in list(self.clients):
            try:
                w.write(line)
            except Exception:
                self.clients.discard(w)

    def broadcast(self, seeked=None):
        self.send_all(self.status())
        if self.mpris:
            self.mpris.update(seeked)

    @property
    def likes(self):
        if getattr(self, "_likes", None) is None:
            self._likes = set(self.lib.like_ids())
        return self._likes

    def library_event(self):
        self._likes = None
        self.send_all({"event": "library", "likes": list(self.likes)})

    def files_event(self):
        self.send_all({"event": "files", "files": self.lib.states(), "progress": self.progress})

    # ═══════════════════ resolving ═══════════════════
    async def url_for(self, vid, conn=None):
        """(url, ua, expires) | None (unplayable). Raises ConnectionError when offline."""
        c = self.cache.get(vid)
        if c and c[2] > time.time():
            return c
        conn = conn or self.res
        try:
            r = await self.run_sync(yt.resolve, conn, vid)
            if r is None:                               # retry once with a fresh visitor id
                conn.visitor = None
                r = await self.run_sync(yt.resolve, conn, vid)
        except (ConnectionError, OSError):
            self.set_online(False)
            raise ConnectionError("offline")
        self.set_online(True)
        if r:
            self.cache[vid] = r
        return r

    def set_online(self, on):
        if self.online != on:
            self.online = on
            if on:
                self.notice = ""
            self.broadcast()

    def prefetch(self):
        n = self.index + 1
        if 0 <= n < len(self.queue) and not self.lib.local(self.queue[n]["id"]):
            asyncio.ensure_future(self.quiet(self.url_for(self.queue[n]["id"])))

    async def quiet(self, coro):
        try:
            await coro
        except Exception:
            pass

    # ═══════════════════ caching + downloads ═══════════════════
    def enqueue_job(self, t, download=False):
        if download:
            self.want_download.add(t["id"])
        self.jobs.put_nowait(t)

    async def job_worker(self):
        while True:
            t = await self.jobs.get()
            try:
                await self.do_job(t)
            except Exception as e:
                log.exception("caching %s failed", t.get("id"))
                if t["id"] in self.want_download:
                    self.notice = f"Couldn't download “{t.get('title', t['id'])}” ({e.__class__.__name__})"
                    self.want_download.discard(t["id"])
                    self.broadcast()
            finally:
                self.progress.pop(t["id"], None)
                self.files_event()

    async def do_job(self, t):
        vid = t["id"]
        self.lib.remember(t)
        states = self.lib.states()
        webm, jpg = self.lib.cache_paths(vid)
        if states.get(vid) is None:
            r = await self.url_for(vid, self.dl)
            if not r:
                raise RuntimeError("unplayable")
            self.progress[vid] = 0.0
            self.files_event()
            last = [0.0]
            loop = asyncio.get_running_loop()

            def prog(p):                                # runs on the download thread
                if p - last[0] >= 0.1:
                    last[0] = p
                    self.progress[vid] = p
                    loop.call_soon_threadsafe(self.files_event)
            await self.run_sync(lambda: yt.fetch_stream(r[0], r[1], webm, prog))
            art = t.get("art") or t.get("thumb")
            if art and art.startswith("http"):
                try:
                    await self.run_sync(yt.fetch_file, art, jpg)
                except Exception:
                    jpg = ""
            self.lib.add_file(vid, "cache", webm, jpg if jpg and os.path.exists(jpg) else "")
        if vid in self.want_download:
            self.want_download.discard(vid)
            if self.lib.states().get(vid) != "download":
                src = self.lib.local(vid)
                await self.run_sync(self.lib.save_download, t, src, self.lib.local_art(vid))
                # the download replaces the cached copy
                self.lib.remove_file(vid, "cache")
            self.notice = ""
        self.broadcast()

    # ═══════════════════ mpv ═══════════════════
    async def ensure_mpv(self):
        # one at a time: commands arriving together ("radio" then "play") must share one mpv,
        # not each start their own (seen: three mpv processes, two of them orphaned)
        if not hasattr(self, "_mpv_lock"):
            self._mpv_lock = asyncio.Lock()
        async with self._mpv_lock:
            return await self._ensure_mpv()

    async def _ensure_mpv(self):
        if self.mpv and self.mpv.returncode is None and self.mw:
            return True
        if self.mpv and self.mpv.returncode is None:      # alive but we lost its socket: replace it
            self.mpv.terminate()
        try:
            os.unlink(MPV_SOCK)
        except OSError:
            pass
        args = ["mpv", "--no-video", "--idle=yes", "--no-terminal", "--force-window=no", "--audio-display=no",
                "--load-scripts=no",                     # no mpv-mpris: we are the MPRIS player
                f"--input-ipc-server={MPV_SOCK}", "--ytdl-format=bestaudio/best", "--cache=yes",
                "--demuxer-max-bytes=8MiB", "--volume-max=130", f"--volume={self.volume}"]
        self.mpv = await asyncio.create_subprocess_exec(*args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(50):
            try:
                r, self.mw = await asyncio.open_unix_connection(MPV_SOCK)
                asyncio.ensure_future(self.mpv_reader(r))
                for i, p in enumerate(("pause", "duration", "volume")):
                    await self.cmd("observe_property", i + 1, p)
                await self.cmd("set_property", "loop-file", "inf" if self.loop_mode == "track" else "no")
                return True
            except OSError:
                await asyncio.sleep(0.1)
        return False

    async def cmd(self, *a):
        if self.mw:
            self.mw.write((json.dumps({"command": list(a)}) + "\n").encode())
            await self.mw.drain()

    async def query_pos(self):
        if self.mw:
            self.mw.write(b'{"command":["get_property","time-pos"],"request_id":99}\n')
            await self.mw.drain()

    async def mpv_reader(self, r):
        try:
            while True:
                line = await r.readline()
                if not line:
                    break
                try:
                    ev = json.loads(line)
                except ValueError:
                    continue
                if ev.get("request_id") == 99:
                    if isinstance(ev.get("data"), (int, float)):
                        self.pos, self.pos_at = ev["data"], time.time()
                        self.broadcast(seeked=self.pos if self.seeking else None)
                        self.seeking = False
                    continue
                e = ev.get("event")
                if e == "property-change":
                    v = ev.get("data")
                    if ev["name"] == "pause":
                        if self.loaded:
                            self.pos = self.live_pos() if not self.paused else self.pos
                        self.paused = bool(v)
                        await self.query_pos()
                    elif ev["name"] == "duration" and v:
                        self.dur = v
                        self.broadcast()
                    elif ev["name"] == "volume" and v is not None:
                        self.volume = round(v)
                elif e == "playback-restart":
                    self.loading = False
                    await self.query_pos()
                elif e == "end-file":
                    if ev.get("reason") in ("eof", "error"):
                        was_loaded = self.loaded
                        self.loaded = False
                        if was_loaded:
                            await self.step(1, reason="eof" if ev.get("reason") == "eof" else "error")
        finally:
            self.mw = None
            self.loaded = False

    seeking = False

    # ═══════════════════ playback ═══════════════════
    def finish_current(self, reason):
        """Record how the current track was listened to before moving on."""
        t = self.cur()
        if t and (self.loaded or reason == "eof"):
            listened = self.dur if reason == "eof" else self.live_pos()
            try:
                self.lib.record(t, listened, self.dur, reason)
            except Exception:
                pass

    async def start(self, offline_skips=0):
        if not (0 <= self.index < len(self.queue)):
            return
        t = self.queue[self.index]
        self.loading, self.loaded = True, True
        self.pos, self.dur, self.pos_at = 0.0, 0.0, time.time()
        self.last_active = time.time()
        self.notice = "" if offline_skips == 0 else self.notice
        self.broadcast()
        if not await self.ensure_mpv():
            self.loading = self.loaded = False
            self.broadcast()
            return
        self.lib.remember(t)
        title = mpv_str(t.get("title") or t["id"])
        local = self.lib.local(t["id"])
        if local:
            self.via = self.lib.states().get(t["id"], "cache")
            await self.cmd("loadfile", local, "replace", -1, f"force-media-title={title}")
        else:
            try:
                r = await self.url_for(t["id"])
            except ConnectionError:
                await self.skip_offline(offline_skips)
                return
            if self.queue[self.index:self.index + 1] != [t]:
                return                                  # skipped again while resolving
            if r:
                self.via = "stream"
                await self.cmd("loadfile", r[0], "replace", -1, f"user-agent={mpv_str(r[1])},force-media-title={title}")
                self.enqueue_job(t)                     # cache it while it plays
            else:
                self.via = "yt-dlp"
                await self.cmd("loadfile", "https://music.youtube.com/watch?v=" + t["id"], "replace", -1,
                               f"force-media-title={title}")
        await self.cmd("set_property", "pause", False)
        self.save()
        self.broadcast()
        self.prefetch()
        if self.autoplay and self.online and self.index >= len(self.queue) - 2:
            asyncio.ensure_future(self.extend_radio())

    async def skip_offline(self, skips):
        """Offline and no local copy: jump to the next track that has one."""
        for i in range(self.index + 1, len(self.queue)):
            if self.lib.local(self.queue[i]["id"]):
                self.notice = "Offline: skipped songs that aren't saved on this computer"
                self.index = i
                await self.start(skips + 1)
                return
        self.loading = self.loaded = False
        self.notice = "You're offline and nothing left in the queue is saved. Play something from Offline."
        self.broadcast()

    async def extend_radio(self):
        if not self.queue:
            return
        seed = self.queue[-1]["id"]
        if seed == self.radio_for:
            return
        self.radio_for = seed
        try:
            more = await self.radio(seed)
        except Exception:
            return
        have = {t["id"] for t in self.queue[-150:]}
        add = [t for t in more if t["id"] not in have][:15]
        if add:
            self.queue.extend(add)
            self.save()
            self.broadcast()
            self.prefetch()

    async def radio(self, seed):
        c = self.radios.get(seed)
        if c and time.time() - c[0] < RADIO_TTL:
            return c[1]
        try:
            tracks = await self.run_sync(yt.watch_list, self.api, seed, "")
        except OSError:
            self.set_online(False)
            raise
        self.set_online(True)
        self.radios[seed] = (time.time(), tracks)
        return tracks

    async def step(self, d, reason="skip"):
        self.finish_current(reason)
        if reason == "eof" and self.sleep_end_track:      # sleep timer: "end of this song"
            self.sleep_end_track = False
            n = self.index + 1
            if 0 <= n < len(self.queue):
                self.index = n
                await self.start()
                await self.cmd("set_property", "pause", True)
            self.broadcast()
            return
        n = self.index + d
        if 0 <= n < len(self.queue):
            self.index = n
            await self.start()
            return
        if d > 0:
            if self.autoplay and self.online:
                await self.extend_radio()
                if self.index + 1 < len(self.queue):
                    self.index += 1
                    await self.start()
                    return
            if self.loop_mode == "queue" and self.queue:
                self.index = 0
                await self.start()
                return
            await self.cmd("stop")
            self.loaded = self.loading = False
            self.broadcast()

    async def set_queue(self, tracks, at=0):
        self.finish_current("skip")
        self.queue, self.index = list(tracks), at
        self.radio_for = ""
        if self.shuffle:
            self.shuffle_upcoming()
        await self.start()

    def shuffle_upcoming(self):
        rest = self.queue[self.index + 1:]
        random.shuffle(rest)
        self.queue = self.queue[:self.index + 1] + rest

    def set_loop(self, mode):
        self.loop_mode = mode if mode in ("none", "track", "queue") else "none"
        asyncio.ensure_future(self.cmd("set_property", "loop-file", "inf" if self.loop_mode == "track" else "no"))

    # ═══════════════════ "For you" ═══════════════════
    async def for_you(self, force=False):
        at, count, tracks = self.foryou
        hist = self.lib.history_count()
        if tracks and not force and time.time() - at < FORYOU_TTL and hist - count < 5:
            return tracks
        seeds = self.lib.seeds()
        if not seeds:
            return []
        radios = {}
        results = await asyncio.gather(*(self.radio(s) for s, _ in seeds), return_exceptions=True)
        for (s, w), r in zip(seeds, results):
            if isinstance(r, list):
                radios[s] = (w, r)
        if not radios:
            return tracks
        rec = self.lib.recommend(radios)
        self.foryou = (time.time(), hist, rec)
        return rec

    # ═══════════════════ commands ═══════════════════
    def track_arg(self, a):
        t = a[0]
        if isinstance(t, str) and t.startswith("{"):    # a JSON track from the command line
            t = json.loads(t)
        t = t if isinstance(t, dict) else {"id": t}
        if "title" not in t:
            known = self.lib.track(t["id"])
            t = dict(known, **t) if known else dict(t, title=t["id"], artist="")
        return {k: t.get(k, "") for k in ("id", "title", "artist", "duration", "thumb", "art")}

    async def handle_cmd(self, c, a):
        self.last_active = time.time()
        if c == "status":
            return self.status()
        if c == "files":
            return {"files": self.lib.states(), "progress": self.progress}
        if c == "search":
            try:
                r = await self.run_sync(yt.search, self.api, a[0])
            except OSError:
                self.set_online(False)
                raise RuntimeError("You're offline")
            self.set_online(True)
            return r
        if c == "home":
            try:
                r = await self.run_sync(yt.home, self.api)
            except OSError:
                self.set_online(False)
                return []
            self.set_online(True)
            return r
        if c == "foryou":
            return await self.for_you(bool(a and a[0]))
        if c == "recent":
            return self.lib.recent_tracks()
        if c == "offline":
            return self.lib.offline()
        if c == "usage":
            return self.lib.usage()
        if c == "radio":
            seed = self.track_arg(a)
            try:
                tracks = await self.radio(seed["id"])
            except Exception:
                tracks = []
            if not tracks or tracks[0]["id"] != seed["id"]:
                tracks = [seed] + [t for t in tracks if t["id"] != seed["id"]]
            await self.set_queue(tracks)
            return True
        if c == "playlist":
            tracks = await self.run_sync(yt.watch_list, self.api, a[1] if len(a) > 1 else "", a[0])
            if tracks:
                await self.set_queue(tracks)
            return bool(tracks)
        if c == "playlist_tracks":                    # play an explicit list (For you, Offline)
            tracks = [self.track_arg([t]) for t in a[0]]
            start = int(a[1]) if len(a) > 1 else 0
            if len(a) > 2 and a[2]:
                random.shuffle(tracks)
                start = 0
            if tracks:
                await self.set_queue(tracks, start)
            return True
        if c == "play":
            t = self.track_arg(a)
            self.finish_current("skip")
            self.queue = self.queue[:self.index + 1] + [t] + self.queue[self.index + 1:]
            self.index += 1
            await self.start()
            return True
        if c == "download":
            t = self.track_arg(a)
            self.lib.remember(t)
            self.enqueue_job(t, download=True)
            self.progress.setdefault(t["id"], 0.0)
            self.files_event()
            return True
        if c == "like":                                # [track, on?] (toggles without `on`)
            t = self.track_arg(a)
            on = bool(a[1]) if len(a) > 1 else t["id"] not in self.likes
            self.lib.like(t, on)
            if on and self.lib.states().get(t["id"]) != "download":
                self.enqueue_job(t, download=True)       # liked songs are kept offline
                self.progress.setdefault(t["id"], 0.0)
                self.files_event()
            self.library_event()
            self.foryou = (0, 0, self.foryou[2])         # likes reshape For you
            self.broadcast()
            return on
        if c == "liked":
            return self.lib.liked()
        if c == "history":
            return self.lib.history()
        if c == "playlists":
            return self.lib.playlists()
        if c == "playlist_get":
            return self.lib.playlist_tracks(int(a[0]))
        if c == "playlist_create":
            pid = self.lib.playlist_create(a[0] if a else "")
            if len(a) > 1 and a[1]:
                self.lib.playlist_add(pid, self.track_arg([a[1]]))
            self.send_all({"event": "playlists"})
            return pid
        if c == "playlist_rename":
            self.lib.playlist_rename(int(a[0]), a[1])
            self.send_all({"event": "playlists"})
            return True
        if c == "playlist_delete":
            self.lib.playlist_delete(int(a[0]))
            self.send_all({"event": "playlists"})
            return True
        if c == "playlist_add":
            added = self.lib.playlist_add(int(a[0]), self.track_arg([a[1]]))
            self.send_all({"event": "playlists"})
            return added
        if c == "playlist_remove":
            self.lib.playlist_remove(int(a[0]), a[1])
            self.send_all({"event": "playlists"})
            return True
        if c == "sleep":                               # minutes | "track" | 0 (off)
            self.set_sleep(a[0] if a else 0)
            self.broadcast()
            return True
        if c == "remove_file":
            self.lib.remove_file(a[0], a[1] if len(a) > 1 else "download")
            self.files_event()
            return True

        if c == "add":
            t = self.track_arg(a)
            self.queue.append(t)
            if not self.loaded:
                self.index = len(self.queue) - 1
                await self.start()
            else:
                self.prefetch()
            self.save()
        elif c == "playnext":
            self.queue.insert(self.index + 1, self.track_arg(a))
            self.prefetch()
            self.save()
        elif c == "remove":
            i = int(a[0])
            if 0 <= i < len(self.queue) and i != self.index:
                del self.queue[i]
                if i < self.index:
                    self.index -= 1
                self.save()
        elif c == "jump":
            self.finish_current("skip")
            self.index = int(a[0])
            await self.start()
        elif c == "next":
            await self.step(1)
        elif c == "prev":
            if self.live_pos() > 4 or self.index <= 0:
                await self.seek_to(0)
            else:
                await self.step(-1, reason="back")
        elif c == "toggle":
            if self.loaded:
                await self.cmd("cycle", "pause")
            elif 0 <= self.index < len(self.queue):
                await self.start()
        elif c == "pause":
            await self.cmd("set_property", "pause", True)
        elif c == "play_resume":
            if self.loaded:
                await self.cmd("set_property", "pause", False)
            elif 0 <= self.index < len(self.queue):
                await self.start()
        elif c == "seek":
            await self.seek_to(float(a[0]))
        elif c == "autoplay":
            self.autoplay = bool(a[0]) if a else not self.autoplay
            self.save()
            if self.autoplay and self.index >= len(self.queue) - 2:
                asyncio.ensure_future(self.extend_radio())
        elif c == "shuffle":
            self.shuffle = bool(a[0]) if a else not self.shuffle
            if self.shuffle:
                self.shuffle_upcoming()
            self.save()
        elif c == "loop":
            order = ["none", "queue", "track"]
            self.set_loop(a[0] if a else order[(order.index(self.loop_mode) + 1) % 3])
            self.save()
        elif c == "volume":
            self.volume = max(0, min(130, int(float(a[0]))))
            await self.cmd("set_property", "volume", self.volume)
            self.save()
        elif c == "clear":
            self.finish_current("skip")
            await self.cmd("stop")
            self.queue, self.index, self.loaded, self.loading = [], -1, False, False
            self.save()
        elif c == "quit":
            self.shutdown()
        else:
            raise ValueError("unknown command " + str(c))
        self.broadcast()
        return True

    async def sleep_after(self, seconds):
        try:
            await asyncio.sleep(seconds)
            await self.cmd("set_property", "pause", True)
        except asyncio.CancelledError:
            return
        self.sleep_at = 0
        self.broadcast()

    def set_sleep(self, arg):
        if self.sleep_task:
            self.sleep_task.cancel()
            self.sleep_task = None
        self.sleep_at, self.sleep_end_track = 0, False
        if arg == "track":
            self.sleep_end_track = True
        elif float(arg or 0) > 0:
            secs = float(arg) * 60
            self.sleep_at = time.time() + secs
            self.sleep_task = asyncio.ensure_future(self.sleep_after(secs))

    async def seek_to(self, s):
        await self.cmd("seek", max(0.0, s), "absolute")
        self.pos, self.pos_at = max(0.0, s), time.time()
        self.seeking = True
        await self.query_pos()

    async def mpris_cmd(self, c, *a):
        """Commands from the desktop (media keys, the shell's Music drawer)."""
        try:
            if c == "seek_rel":
                await self.seek_to(self.live_pos() + a[0])
            elif c == "play":
                await self.handle_cmd("play_resume", [])
            elif c == "set":
                prop, v = a
                if prop == "Shuffle":
                    await self.handle_cmd("shuffle", [bool(v)])
                elif prop == "LoopStatus":
                    await self.handle_cmd("loop", [{"None": "none", "Track": "track", "Playlist": "queue"}.get(str(v), "none")])
                elif prop == "Volume":
                    await self.handle_cmd("volume", [float(v) * 100])
            else:
                await self.handle_cmd(c, list(a))
        except Exception:
            pass

    # ═══════════════════ socket ═══════════════════
    async def handle(self, r, w):
        self.clients.add(w)
        w.write((json.dumps(self.status()) + "\n").encode())
        w.write((json.dumps({"event": "files", "files": self.lib.states(), "progress": self.progress}) + "\n").encode())
        w.write((json.dumps({"event": "library", "likes": list(self.likes)}) + "\n").encode())
        try:
            while True:
                line = await r.readline()
                if not line:
                    break
                try:
                    req = json.loads(line)
                except ValueError:
                    continue
                asyncio.ensure_future(self.reply(w, req))
        except (ConnectionError, OSError):
            pass                                        # client went away mid-write
        finally:
            self.clients.discard(w)
            self.last_active = time.time()
            w.close()

    async def reply(self, w, req):
        try:
            res = {"id": req.get("id"), "result": await self.handle_cmd(req.get("cmd"), req.get("args") or [])}
        except Exception as e:
            log.exception("command %s failed", req.get("cmd"))
            res = {"id": req.get("id"), "error": str(e)}
        try:
            w.write((json.dumps(res) + "\n").encode())
            await w.drain()
        except Exception:
            self.clients.discard(w)

    def shutdown(self):
        self.finish_current("stop")
        self.save()
        if self.mpv and self.mpv.returncode is None:
            self.mpv.terminate()
        for p in (SOCK, MPV_SOCK):
            try:
                os.unlink(p)
            except OSError:
                pass
        os._exit(0)

    async def idle_watch(self):
        while True:
            await asyncio.sleep(30)
            busy = self.clients or (self.loaded and not self.paused) or self.progress or not self.jobs.empty()
            if busy:
                self.last_active = time.time()
            elif time.time() - self.last_active > IDLE_EXIT:
                self.shutdown()

    async def run(self):
        try:
            os.unlink(SOCK)
        except OSError:
            pass
        self.jobs = asyncio.Queue()
        srv = await asyncio.start_unix_server(self.handle, SOCK)
        os.chmod(SOCK, 0o600)
        loop = asyncio.get_running_loop()
        self.mpris = mpris.Mpris(loop, self.mpris_state, self.mpris_cmd)
        asyncio.ensure_future(self.idle_watch())
        asyncio.ensure_future(self.job_worker())
        asyncio.ensure_future(self.quiet(self.run_sync(self.res.ensure_visitor)))   # warm the connection
        async with srv:
            await srv.serve_forever()


# ═══════════════════ CLI ═══════════════════
def spawn_daemon():
    subprocess.Popen([sys.executable, "-I", os.path.realpath(__file__), "--daemon"],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    for _ in range(50):
        if os.path.exists(SOCK):
            return
        time.sleep(0.1)


def send(cmd, args):
    s = None
    for attempt in range(2):
        try:
            s = socket.socket(socket.AF_UNIX)
            s.settimeout(60)
            s.connect(SOCK)
            break
        except OSError:
            if attempt:
                return {"error": "daemon unavailable"}
            spawn_daemon()
    s.sendall((json.dumps({"id": 1, "cmd": cmd, "args": args}) + "\n").encode())
    for line in s.makefile():
        msg = json.loads(line)
        if msg.get("id") == 1:
            return msg.get("result", msg)
    return {"error": "no reply"}


def main():
    a = sys.argv[1:]
    if not a or a[0] in ("-h", "--help"):
        print(__doc__)
    elif a[0] == "--daemon":
        os.makedirs(STATE_DIR, exist_ok=True)
        logging.basicConfig(filename=LOG_FILE, level=logging.WARNING,
                            format="%(asctime)s %(levelname)s %(message)s")
        try:
            socket.socket(socket.AF_UNIX).connect(SOCK)
            return                                     # already running
        except OSError:
            pass
        asyncio.run(Daemon().run())
    elif a[0] == "--spawn":
        try:
            socket.socket(socket.AF_UNIX).connect(SOCK)
        except OSError:
            spawn_daemon()
    else:
        print(json.dumps(send(a[0], a[1:])))


if __name__ == "__main__":
    main()
