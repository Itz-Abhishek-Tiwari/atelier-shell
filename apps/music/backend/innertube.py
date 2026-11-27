"""InnerTube (YouTube Music's private API) for Atelier Music: search, home, radio and
direct stream URLs. Stdlib only; one kept-alive HTTPS connection per InnerTube object.

Stream URLs come from the visionOS / Android VR player clients, which answer with plain audio
URLs (no player-script solving), ~0.2 s on a warm connection."""
import http.client, json, os, re, threading, time

WEB_UA = "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
WEB_REMIX = {"clientName": "WEB_REMIX", "clientVersion": "1.20250101.01.00", "hl": "en"}
# Clients whose /player answer carries plain audio URLs (tried in order).
STREAM_CLIENTS = [
    ("VISIONOS", "1.02", "101",
     "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
     {"osName": "visionOS", "osVersion": "26.5.23O471", "deviceMake": "Apple", "deviceModel": "RealityDevice17,1"}),
    ("VISIONOS", "0.1", "101",
     "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
     {"osName": "VISION_OS", "osVersion": "1.3", "deviceMake": "Apple", "deviceModel": "RealityDevice14,1", "platform": "MOBILE"}),
    ("ANDROID_VR", "1.61.48", "28",
     "com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
     {"osName": "Android", "osVersion": "12L", "deviceMake": "Oculus", "deviceModel": "Quest 3", "androidSdkVersion": 32}),
]
PLAYER_MASK = "playabilityStatus.status,streamingData.adaptiveFormats,streamingData.expiresInSeconds"


# ═══════════════════════════════ InnerTube ═══════════════════════════════
class InnerTube:
    """One kept-alive HTTPS connection to music.youtube.com (not thread-safe: one per user)."""

    def __init__(self):
        self.conn = None
        self.lock = threading.Lock()
        self.visitor = None

    def post(self, endpoint, body, headers=None):
        h = {"Content-Type": "application/json", "User-Agent": WEB_UA, "Origin": "https://music.youtube.com"}
        h.update(headers or {})
        data = json.dumps(body)
        with self.lock:
            for attempt in range(2):
                try:
                    if self.conn is None:
                        self.conn = http.client.HTTPSConnection("music.youtube.com", timeout=12)
                    self.conn.request("POST", f"/youtubei/v1/{endpoint}?prettyPrint=false", data, h)
                    r = self.conn.getresponse()
                    raw = r.read()
                    if r.status != 200:
                        raise RuntimeError(f"HTTP {r.status}")
                    return json.loads(raw)
                except (http.client.HTTPException, OSError):
                    if self.conn:
                        self.conn.close()
                    self.conn = None
                    if attempt:
                        raise

    def web(self, endpoint, body):
        body = dict(body, context={"client": dict(WEB_REMIX, **({"visitorData": self.visitor} if self.visitor else {}))})
        d = self.post(endpoint, body)
        self.visitor = self.visitor or d.get("responseContext", {}).get("visitorData")
        return d

    def ensure_visitor(self):
        if not self.visitor:
            d = self.post("visitor_id", {"context": {"client": WEB_REMIX}})
            self.visitor = d.get("responseContext", {}).get("visitorData")
        return self.visitor


def walk(o, key):
    if isinstance(o, dict):
        if key in o:
            yield o[key]
        for v in o.values():
            yield from walk(v, key)
    elif isinstance(o, list):
        for v in o:
            yield from walk(v, key)


def first(o, key, default=None):
    return next(walk(o, key), default)


def runs_text(o):
    return "".join(r.get("text", "") for r in (o or {}).get("runs", []))


def sized(url, n):
    """Google image URLs carry their size (=w60-h60…): ask for n×n instead."""
    if not url:
        return ""
    if "googleusercontent.com" in url or "ggpht.com" in url:
        # the size spec is the last "=…" segment: =w60-h60-l90-rj or =s226-c-k-…
        base = re.sub(r"=(w\d+|s\d+)[^/=]*$", "", url)
        return f"{base}=w{n}-h{n}-l90-rj"
    return url


def thumbs(o):
    ts = first(o, "thumbnails", []) or []
    u = ts[-1]["url"] if ts else ""
    return sized(u, 120), sized(u, 544)


def track_from_list_item(it):
    """musicResponsiveListItemRenderer → track (songs and videos only)."""
    vid = (it.get("playlistItemData") or {}).get("videoId") or first(it.get("overlay", {}), "videoId")
    if not vid:
        return None
    cols = it.get("flexColumns", [])
    title = runs_text(first(cols[0], "text")) if cols else ""
    runs = first(cols[1], "runs", []) if len(cols) > 1 else []
    parts = [r["text"] for r in runs if r.get("text", "").strip() not in ("•", "·", "&", ",", "")]
    if parts and parts[0] in ("Song", "Video", "Episode"):
        parts = parts[1:]
    dur = runs_text(first(it.get("fixedColumns", [{}]), "text")) if it.get("fixedColumns") else ""
    if not dur and parts and re.fullmatch(r"\d+(:\d\d)+", parts[-1]):
        dur = parts[-1]
    th, art = thumbs(it.get("thumbnail", {}))
    return {"id": vid, "title": title, "artist": parts[0] if parts else "", "duration": dur, "thumb": th, "art": art}


def track_from_panel(v):
    """playlistPanelVideoRenderer (the /next queue) → track."""
    th, art = thumbs(v.get("thumbnail", {}))
    byline = [r["text"] for r in (v.get("longBylineText") or v.get("shortBylineText") or {}).get("runs", [])]
    return {"id": v["videoId"], "title": runs_text(v.get("title")), "artist": byline[0] if byline else "",
            "duration": runs_text(v.get("lengthText")), "thumb": th, "art": art}


def card_from_two_row(it):
    """musicTwoRowItemRenderer (home cards: albums, playlists, mixes, songs) → card."""
    title = runs_text(it.get("title"))
    sub = runs_text(it.get("subtitle"))
    th, art = thumbs(it.get("thumbnailRenderer", {}))
    nav = it.get("navigationEndpoint", {})
    play = first(it.get("thumbnailOverlay", {}), "playNavigationEndpoint", {}) or {}
    we = nav.get("watchEndpoint") or play.get("watchEndpoint") or {}
    wpe = play.get("watchPlaylistEndpoint") or nav.get("watchPlaylistEndpoint") or {}
    vid, pl = we.get("videoId", ""), we.get("playlistId") or wpe.get("playlistId", "")
    if not vid and not pl:
        return None
    return {"kind": "song" if vid and not wpe else "list", "id": vid, "playlistId": pl,
            "title": title, "artist": sub, "thumb": th, "art": art}


def search(it, q):
    d = it.web("search", {"query": q, "params": "EgWKAQIIAWoMEA4QChADEAQQCRAF"})   # "Songs" filter
    out = [t for t in (track_from_list_item(x) for x in walk(d, "musicResponsiveListItemRenderer")) if t]
    return out[:30]


def home(it):
    d = it.web("browse", {"browseId": "FEmusic_home"})
    shelves = []
    for sh in walk(d, "musicCarouselShelfRenderer"):
        title = runs_text(first(sh.get("header", {}), "title"))
        items = []
        for c in sh.get("contents", []):
            if "musicResponsiveListItemRenderer" in c:
                t = track_from_list_item(c["musicResponsiveListItemRenderer"])
                if t:
                    items.append(dict(t, kind="song", playlistId=""))
            elif "musicTwoRowItemRenderer" in c:
                t = card_from_two_row(c["musicTwoRowItemRenderer"])
                if t:
                    items.append(t)
        if title and items:
            shelves.append({"title": title, "items": items[:20]})
    return shelves


def watch_list(it, vid="", playlist=""):
    """/next: a song's radio (playlist RDAMVM<id>) or the tracks of an album / playlist / mix."""
    body = {"isAudioOnly": True, "enablePersistentPlaylistPanel": True}
    if vid:
        body["videoId"] = vid
    body["playlistId"] = playlist or ("RDAMVM" + vid)
    d = it.web("next", body)
    out, seen = [], set()
    for v in walk(d, "playlistPanelVideoRenderer"):
        if v.get("videoId") and v["videoId"] not in seen:
            seen.add(v["videoId"])
            out.append(track_from_panel(v))
    return out


def resolve(it, vid):
    """Direct audio URL for a video: (url, user_agent, expires_at) or None."""
    vis = it.ensure_visitor()            # raises OSError when offline
    reached = False
    for name, ver, cid, ua, extra in STREAM_CLIENTS:
        client = dict(clientName=name, clientVersion=ver, hl="en", gl="US", visitorData=vis, **extra)
        try:
            d = it.post("player", {"context": {"client": client}, "videoId": vid, "contentCheckOk": True, "racyCheckOk": True},
                        {"User-Agent": ua, "X-Youtube-Client-Name": cid, "X-Youtube-Client-Version": ver,
                         "X-Goog-Visitor-Id": vis or "", "X-Goog-FieldMask": PLAYER_MASK})
        except (OSError, http.client.HTTPException):
            continue
        except Exception:
            reached = True
            continue
        reached = True
        if d.get("playabilityStatus", {}).get("status") != "OK":
            continue
        sd = d.get("streamingData", {})
        audio = [f for f in sd.get("adaptiveFormats", []) if f.get("mimeType", "").startswith("audio") and f.get("url")]
        if audio:
            best = max(audio, key=lambda f: f.get("bitrate", 0))
            return best["url"], ua, time.time() + int(sd.get("expiresInSeconds", 18000)) - 120
    if not reached:
        raise ConnectionError("YouTube Music is unreachable")
    return None


# ═══════════════════════════════ downloading ═══════════════════════════════
CHUNK = 4 << 20    # googlevideo throttles long single reads; 4 MiB ranges stay at full speed


def fetch_stream(url, ua, dest, progress=None, cancelled=lambda: False):
    """Download a stream URL to dest (via dest.part) in ranged chunks. Returns the size."""
    import urllib.request
    part = dest + ".part"
    done, total = 0, None
    try:
        with open(part, "wb") as f:
            while total is None or done < total:
                if cancelled():
                    raise InterruptedError("cancelled")
                req = urllib.request.Request(url, headers={"User-Agent": ua, "Range": f"bytes={done}-{done + CHUNK - 1}"})
                with urllib.request.urlopen(req, timeout=20) as r:
                    if total is None:
                        cr = r.headers.get("Content-Range", "")
                        total = int(cr.rsplit("/", 1)[1]) if "/" in cr and not cr.endswith("*") else int(r.headers.get("Content-Length", 0))
                    data = r.read()
                if not data:
                    break
                f.write(data)
                done += len(data)
                if progress and total:
                    progress(done / total)
        if total and done < total:
            raise IOError("incomplete download")
        os.replace(part, dest)
        return done
    except BaseException:
        try:
            os.unlink(part)
        except OSError:
            pass
        raise


def fetch_file(url, dest, ua=WEB_UA):
    import urllib.request
    req = urllib.request.Request(url, headers={"User-Agent": ua})
    with urllib.request.urlopen(req, timeout=15) as r:
        data = r.read()
    with open(dest + ".part", "wb") as f:
        f.write(data)
    os.replace(dest + ".part", dest)
