"""Atelier Music's library: listening history, offline files and "For you" recommendations.

Storage (settings in ~/.config/atelier/music.json, all optional):
  {"storage": "/mnt/games/AtelierMusic", "cacheLimitGB": 5}
  <storage>/cache/      every song you play (<id>.webm + <id>.jpg), least recently played
                        removed first once the cache passes cacheLimitGB
  <storage>/downloads/  songs you download ("Artist - Title.opus" + .covers/), never removed
                        automatically
If the storage drive isn't mounted, everything falls back to ~/.local/share/atelier-music.

History lives in $XDG_STATE_HOME/atelier-music/library.db (SQLite).
"""
import json, math, os, re, shutil, sqlite3, subprocess, threading, time

STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "atelier-music")
CONFIG = os.path.expanduser("~/.config/atelier/music.json")
DEFAULT_STORAGE = "/mnt/games/AtelierMusic"
FALLBACK_STORAGE = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "atelier-music")


def load_config():
    try:
        with open(CONFIG) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def usable_dir(path):
    """True when path (or its nearest existing parent) is on a mounted, writable filesystem."""
    p = path
    while not os.path.exists(p):
        p = os.path.dirname(p)
    if p.startswith("/mnt/") or p.startswith("/media/") or p.startswith("/run/media/"):
        # the drive has to be mounted, not just its empty mount point
        root = "/" + "/".join(path.strip("/").split("/")[:2])
        if not os.path.ismount(root):
            return False
    return os.access(p, os.W_OK)


def safe_name(s):
    s = re.sub(r'[\\/:*?"<>|\x00-\x1f]', "", s).strip().strip(".")
    return s[:120] or "track"


class _Rows(list):
    def fetchone(self):
        return self[0] if self else None

    def fetchall(self):
        return list(self)


class LockedDB:
    """One SQLite connection shared by the daemon, its download threads and the MPRIS thread:
    every statement runs under a lock and its rows are fetched before the lock is released."""

    def __init__(self, path):
        self.c = sqlite3.connect(path, check_same_thread=False)
        self.c.row_factory = sqlite3.Row
        self.lock = threading.RLock()

    def execute(self, sql, params=()):
        with self.lock:
            return _Rows(self.c.execute(sql, params).fetchall())

    def executescript(self, sql):
        with self.lock:
            self.c.executescript(sql)

    def commit(self):
        with self.lock:
            self.c.commit()


class Library:
    def __init__(self):
        cfg = load_config()
        want = os.path.expanduser(cfg.get("storage") or DEFAULT_STORAGE)
        self.storage = want if usable_dir(want) else FALLBACK_STORAGE
        self.on_fallback = self.storage != want
        self.cache_dir = os.path.join(self.storage, "cache")
        self.dl_dir = os.path.join(self.storage, "downloads")
        self.cover_dir = os.path.join(self.dl_dir, ".covers")
        for d in (self.cache_dir, self.cover_dir, STATE_DIR):
            os.makedirs(d, exist_ok=True)
        lim = cfg.get("cacheLimitGB", 5)
        self.cache_limit = None if lim in (None, 0, "none") else int(float(lim) * (1 << 30))

        self.db = LockedDB(os.path.join(STATE_DIR, "library.db"))
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS likes (id TEXT PRIMARY KEY, ts REAL);
            CREATE TABLE IF NOT EXISTS playlists (pid INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, created REAL, updated REAL);
            CREATE TABLE IF NOT EXISTS playlist_items (pid INTEGER, pos INTEGER, id TEXT, added REAL);
            CREATE INDEX IF NOT EXISTS playlist_items_pid ON playlist_items(pid, pos);
            CREATE TABLE IF NOT EXISTS tracks (
                id TEXT PRIMARY KEY, title TEXT, artist TEXT, duration TEXT, thumb TEXT, art TEXT,
                plays INTEGER DEFAULT 0, completes INTEGER DEFAULT 0, skips INTEGER DEFAULT 0,
                listened REAL DEFAULT 0, first_played REAL, last_played REAL);
            CREATE TABLE IF NOT EXISTS events (ts REAL, id TEXT, kind TEXT, secs REAL);
            CREATE INDEX IF NOT EXISTS events_ts ON events(ts);
        """)
        # files: one row per (song, kind) — a song can be both cached and downloaded.
        # (early builds keyed it on id alone: rebuild that table, keeping its rows)
        cols = self.db.execute("PRAGMA table_info(files)")
        if cols and sum(1 for c in cols if c["pk"]) == 1:
            self.db.executescript("ALTER TABLE files RENAME TO files_old;")
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS files (
                id TEXT, kind TEXT, path TEXT, art TEXT, size INTEGER, added REAL, used REAL,
                PRIMARY KEY (id, kind));
        """)
        if cols and sum(1 for c in cols if c["pk"]) == 1:
            self.db.executescript("INSERT OR IGNORE INTO files SELECT * FROM files_old; DROP TABLE files_old;")
        self.db.commit()
        self.forget_missing()

    # ── tracks ──
    def remember(self, t):
        self.db.execute("""INSERT INTO tracks (id, title, artist, duration, thumb, art) VALUES (?,?,?,?,?,?)
                           ON CONFLICT(id) DO UPDATE SET title=excluded.title, artist=excluded.artist,
                           duration=COALESCE(NULLIF(excluded.duration,''), duration),
                           thumb=COALESCE(NULLIF(excluded.thumb,''), thumb), art=COALESCE(NULLIF(excluded.art,''), art)""",
                        (t["id"], t.get("title", ""), t.get("artist", ""), t.get("duration", ""), t.get("thumb", ""), t.get("art", "")))
        self.db.commit()

    def track(self, vid):
        r = self.db.execute("SELECT * FROM tracks WHERE id=?", (vid,)).fetchone()
        return dict(r) if r else None

    def record(self, t, listened, dur, reason):
        """A track stopped: classify it as a full listen, a skip, or a play."""
        if not t or listened < 1:
            return
        self.remember(t)
        dur = dur or 0
        if reason == "eof" or (dur and listened >= 0.8 * dur):
            kind = "complete"
        elif reason == "skip" and listened < min(30, 0.5 * dur if dur else 30):
            kind = "skip"
        elif listened >= 10:
            kind = "play"
        else:
            return
        now = time.time()
        self.db.execute("INSERT INTO events VALUES (?,?,?,?)", (now, t["id"], kind, listened))
        self.db.execute(f"""UPDATE tracks SET listened = listened + ?, last_played = ?,
                            first_played = COALESCE(first_played, ?),
                            plays = plays + ?, completes = completes + ?, skips = skips + ? WHERE id = ?""",
                        (listened, now, now, kind != "skip", kind == "complete", kind == "skip", t["id"]))
        self.db.commit()

    # ── offline files ──
    def local(self, vid):
        """Path of a playable local copy (download first, then cache), or None."""
        for kind in ("download", "cache"):
            r = self.db.execute("SELECT path FROM files WHERE id=? AND kind=?", (vid, kind)).fetchone()
            if r and os.path.exists(r["path"]):
                self.db.execute("UPDATE files SET used=? WHERE id=? AND kind=?", (time.time(), vid, kind))
                self.db.commit()
                return r["path"]
        return None

    def local_art(self, vid):
        for kind in ("download", "cache"):
            r = self.db.execute("SELECT art FROM files WHERE id=? AND kind=?", (vid, kind)).fetchone()
            if r and r["art"] and os.path.exists(r["art"]):
                return r["art"]
        return None

    def states(self):
        """{videoId: "download" | "cache"} for every local copy."""
        out = {}
        for r in self.db.execute("SELECT id, kind FROM files"):
            if out.get(r["id"]) != "download":
                out[r["id"]] = r["kind"]
        return out

    def cache_paths(self, vid):
        return os.path.join(self.cache_dir, vid + ".webm"), os.path.join(self.cache_dir, vid + ".jpg")

    def add_file(self, vid, kind, path, art):
        self.db.execute("DELETE FROM files WHERE id=? AND kind=?", (vid, kind))
        self.db.execute("INSERT INTO files (id, kind, path, art, size, added, used) VALUES (?,?,?,?,?,?,?)",
                        (vid, kind, path, art, os.path.getsize(path), time.time(), time.time()))
        self.db.commit()
        if kind == "cache":
            self.evict()

    def remove_file(self, vid, kind):
        for r in self.db.execute("SELECT path, art FROM files WHERE id=? AND kind=?", (vid, kind)).fetchall():
            for p in (r["path"], r["art"]):
                try:
                    if p:
                        os.unlink(p)
                except OSError:
                    pass
        self.db.execute("DELETE FROM files WHERE id=? AND kind=?", (vid, kind))
        self.db.commit()

    def evict(self, keep=()):
        if not self.cache_limit:
            return
        rows = self.db.execute("SELECT id, size FROM files WHERE kind='cache' ORDER BY used ASC").fetchall()
        total = sum(r["size"] or 0 for r in rows)
        for r in rows:
            if total <= self.cache_limit:
                break
            if r["id"] in keep:
                continue
            self.remove_file(r["id"], "cache")
            total -= r["size"] or 0

    def forget_missing(self):
        """Drop rows whose files were deleted by hand (or whose drive isn't the current storage)."""
        for r in self.db.execute("SELECT id, kind, path FROM files").fetchall():
            if not os.path.exists(r["path"]):
                self.db.execute("DELETE FROM files WHERE id=? AND kind=?", (r["id"], r["kind"]))
        self.db.commit()

    def download_path(self, t):
        name = safe_name(f'{t.get("artist") or "Unknown"} - {t.get("title") or t["id"]}')
        p = os.path.join(self.dl_dir, name + ".opus")
        if os.path.exists(p):
            p = os.path.join(self.dl_dir, f'{name} [{t["id"]}].opus')
        return p, os.path.join(self.cover_dir, t["id"] + ".jpg")

    def save_download(self, t, src_webm, art_src):
        """Remux a cached/downloaded webm into a tagged .opus in downloads/ (ffmpeg; else copy)."""
        dest, cover = self.download_path(t)
        tmp = dest + ".part.opus"
        try:
            subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", src_webm, "-vn", "-c:a", "copy",
                            # Ogg Opus keeps its tags on the audio stream
                            "-metadata:s:a:0", f"title={t.get('title', '')}",
                            "-metadata:s:a:0", f"artist={t.get('artist', '')}",
                            "-metadata:s:a:0", f"comment=https://music.youtube.com/watch?v={t['id']}", tmp],
                           check=True, timeout=120)
            os.replace(tmp, dest)
        except (OSError, subprocess.SubprocessError):
            try:
                os.unlink(tmp)
            except OSError:
                pass
            dest = os.path.splitext(dest)[0] + ".webm"
            shutil.copyfile(src_webm, dest)
        if art_src and os.path.exists(art_src):
            shutil.copyfile(art_src, cover)
        else:
            cover = ""
        self.add_file(t["id"], "download", dest, cover)
        return dest

    def offline(self):
        """Every track with a local copy, newest first, with its metadata."""
        rows = self.db.execute("""SELECT f.id, f.kind, f.size, f.added, f.art AS local_art, t.title, t.artist,
                                  t.duration, t.thumb, t.art, t.plays FROM files f LEFT JOIN tracks t ON t.id = f.id
                                  ORDER BY f.added DESC""").fetchall()
        seen, out = {}, []
        for r in rows:
            d = dict(r)
            if d["id"] in seen:
                if d["kind"] == "download":
                    seen[d["id"]]["kind"] = "download"
                continue
            if d.get("local_art"):
                d["thumb"] = d["art"] = "file://" + d["local_art"]
            d["title"] = d["title"] or d["id"]
            d["artist"] = d["artist"] or ""
            seen[d["id"]] = d
            out.append(d)
        return out

    def usage(self):
        def total(kind):
            r = self.db.execute("SELECT COALESCE(SUM(size),0) AS s, COUNT(*) AS n FROM files WHERE kind=?", (kind,)).fetchone()
            return r["s"], r["n"]
        cs, cn = total("cache")
        ds, dn = total("download")
        return {"storage": self.storage, "fallback": self.on_fallback, "cacheBytes": cs, "cacheCount": cn,
                "cacheLimit": self.cache_limit or 0, "downloadBytes": ds, "downloadCount": dn}

    # ── likes ──
    def like(self, t, on=True):
        self.remember(t)
        if on:
            self.db.execute("INSERT OR IGNORE INTO likes VALUES (?, ?)", (t["id"], time.time()))
        else:
            self.db.execute("DELETE FROM likes WHERE id=?", (t["id"],))
        self.db.commit()

    def like_ids(self):
        return [r["id"] for r in self.db.execute("SELECT id FROM likes ORDER BY ts DESC")]

    def _tracks(self, rows):
        """rows with an `id` column → full track dicts (with local covers when saved)."""
        out = []
        for r in rows:
            t = self.track(r["id"])
            if not t:
                continue
            la = self.local_art(t["id"])
            if la:
                t["thumb"] = t["art"] = "file://" + la
            out.append({k: t.get(k) or "" for k in ("id", "title", "artist", "duration", "thumb", "art")})
        return out

    def liked(self):
        return self._tracks(self.db.execute("SELECT id FROM likes ORDER BY ts DESC"))

    # ── playlists (local) ──
    def playlists(self):
        out = []
        for r in self.db.execute("SELECT * FROM playlists ORDER BY updated DESC"):
            items = self.db.execute("SELECT id FROM playlist_items WHERE pid=? ORDER BY pos LIMIT 4", (r["pid"],))
            n = self.db.execute("SELECT COUNT(*) AS n FROM playlist_items WHERE pid=?", (r["pid"],)).fetchone()["n"]
            covers = [t["art"] or t["thumb"] for t in self._tracks(items)]
            out.append({"pid": r["pid"], "name": r["name"], "count": n, "covers": covers})
        return out

    def playlist_create(self, name):
        now = time.time()
        self.db.execute("INSERT INTO playlists (name, created, updated) VALUES (?, ?, ?)", (name.strip() or "New playlist", now, now))
        self.db.commit()
        return self.db.execute("SELECT MAX(pid) AS pid FROM playlists").fetchone()["pid"]

    def playlist_rename(self, pid, name):
        self.db.execute("UPDATE playlists SET name=?, updated=? WHERE pid=?", (name.strip() or "Playlist", time.time(), pid))
        self.db.commit()

    def playlist_delete(self, pid):
        self.db.execute("DELETE FROM playlist_items WHERE pid=?", (pid,))
        self.db.execute("DELETE FROM playlists WHERE pid=?", (pid,))
        self.db.commit()

    def playlist_add(self, pid, t):
        self.remember(t)
        if self.db.execute("SELECT 1 FROM playlist_items WHERE pid=? AND id=?", (pid, t["id"])).fetchone():
            return False                                    # already in it
        pos = self.db.execute("SELECT COALESCE(MAX(pos), -1) + 1 AS p FROM playlist_items WHERE pid=?", (pid,)).fetchone()["p"]
        self.db.execute("INSERT INTO playlist_items VALUES (?, ?, ?, ?)", (pid, pos, t["id"], time.time()))
        self.db.execute("UPDATE playlists SET updated=? WHERE pid=?", (time.time(), pid))
        self.db.commit()
        return True

    def playlist_remove(self, pid, vid):
        self.db.execute("DELETE FROM playlist_items WHERE pid=? AND id=?", (pid, vid))
        self.db.commit()

    def playlist_tracks(self, pid):
        return self._tracks(self.db.execute("SELECT id FROM playlist_items WHERE pid=? ORDER BY pos", (pid,)))

    # ── history ──
    def history(self, limit=150):
        rows = self.db.execute("""SELECT e.id, MAX(e.ts) AS ts FROM events e WHERE e.kind != 'skip'
                                  GROUP BY e.id ORDER BY ts DESC LIMIT ?""", (limit,))
        when = {r["id"]: r["ts"] for r in rows}
        out = self._tracks(rows)
        for t in out:
            t["played"] = when.get(t["id"], 0)
        return out

    # ── "For you" ────────────────────────────────────────────────────────────
    # 1. Every track you've played gets an affinity score:
    #       (plays + 2·full listens − 1.5·skips) × 0.5^(days since last played / 14)
    #    so recent favourites weigh most and songs you skip sink.
    # 2. Artists get the sum of their tracks' scores (artist affinity).
    # 3. Seeds: your top tracks (at most 2 per artist) plus your 3 latest plays.
    # 4. Each seed's YouTube Music radio is fetched (by the daemon); a candidate scores
    #       Σ over seeds of seed weight × (1 − its rank in that radio)
    #    so songs that show up in several of your radios rise to the top, then
    #       + 0.3 × artist affinity (normalised)   × 1.25 if you've never played it
    #       × 0.3 if you played it in the last 3 days   dropped if you skip it more than you finish it.
    # 5. At most 3 songs per artist, interleaved so the same artist doesn't play back to back.
    def scores(self):
        now = time.time()
        out = {}
        for r in self.db.execute("SELECT * FROM tracks WHERE plays > 0 OR skips > 0"):
            days = (now - (r["last_played"] or now)) / 86400
            s = (r["plays"] + 2 * r["completes"] - 1.5 * r["skips"]) * math.pow(0.5, days / 14)
            out[r["id"]] = (s, dict(r))
        # a like is a strong, lasting signal: +6, and it doesn't fade with time
        for r in self.db.execute("SELECT t.* FROM likes l JOIN tracks t ON t.id = l.id"):
            s, t = out.get(r["id"], (0, dict(r)))
            out[r["id"]] = (s + 6, t)
        return out

    def seeds(self, n=6):
        sc = self.scores()
        ranked = sorted(sc.values(), key=lambda x: -x[0])
        per_artist, seeds = {}, []
        for s, t in ranked:
            if s <= 0 or len(seeds) >= n:
                break
            a = (t["artist"] or "").lower()
            if per_artist.get(a, 0) >= 2:
                continue
            per_artist[a] = per_artist.get(a, 0) + 1
            seeds.append((t["id"], s))
        for r in self.db.execute("SELECT id FROM events WHERE kind != 'skip' ORDER BY ts DESC LIMIT 30"):
            if len([1 for i, _ in seeds if i == r["id"]]) == 0 and len(seeds) < n + 3:
                seeds.append((r["id"], max([w for _, w in seeds] or [1]) * 0.6))
        return seeds

    def recommend(self, radios, limit=30):
        """radios: {seed_id: (seed_weight, [tracks…])} → ranked list of tracks."""
        sc = self.scores()
        artist_aff = {}
        for s, t in sc.values():
            a = (t["artist"] or "").lower()
            artist_aff[a] = artist_aff.get(a, 0) + max(0, s)
        top_aff = max(artist_aff.values() or [1]) or 1
        recent = {r["id"] for r in self.db.execute("SELECT id FROM events WHERE ts > ?", (time.time() - 3 * 86400,))}
        cand = {}
        for seed, (w, tracks) in radios.items():
            n = max(1, len(tracks))
            for i, t in enumerate(tracks):
                if t["id"] == seed:
                    continue
                c = cand.setdefault(t["id"], {"t": t, "s": 0.0})
                c["s"] += max(w, 0.1) * (1 - i / n)
        out = []
        for vid, c in cand.items():
            t, s = c["t"], c["s"]
            known = sc.get(vid)
            if known:
                _, k = known
                if k["skips"] > k["completes"] + 1:
                    continue
            else:
                s *= 1.25
            if vid in recent:
                s *= 0.3
            s += 0.3 * artist_aff.get((t.get("artist") or "").lower(), 0) / top_aff
            out.append((s, t))
        out.sort(key=lambda x: -x[0])
        # diversity: ≤ 3 per artist, then interleave so one artist doesn't run back to back
        per, picked = {}, []
        for s, t in out:
            a = (t.get("artist") or "").lower()
            if per.get(a, 0) >= 3:
                continue
            per[a] = per.get(a, 0) + 1
            picked.append(t)
            if len(picked) >= limit:
                break
        result, last = [], None
        pool = picked[:]
        while pool:
            i = next((k for k, t in enumerate(pool) if (t.get("artist") or "").lower() != last), 0)
            t = pool.pop(i)
            last = (t.get("artist") or "").lower()
            result.append(t)
        return result

    def history_count(self):
        return self.db.execute("SELECT COUNT(*) FROM events").fetchone()[0]

    def recent_tracks(self, limit=12):
        rows = self.db.execute("""SELECT t.* FROM tracks t JOIN (SELECT id, MAX(ts) AS ts FROM events
                                  WHERE kind != 'skip' GROUP BY id) e ON e.id = t.id ORDER BY e.ts DESC LIMIT ?""", (limit,))
        return [dict(r) for r in rows]
