"""Stream a plain-text Gemini answer for Atelier's launcher.

Gemini's API sometimes sits on a request for ~10 s (or answers 503) while a retry a moment later
returns in about a second. So the request is hedged: if the first model has not produced a token
after HEDGE_AFTER seconds, the same question is sent to the next model in parallel, and whichever
streams a token first wins. Nothing is printed until a winner exists, so an answer never mixes.
"""

import json
import os
from pathlib import Path
import queue
import sys
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

MODELS = ["gemini-3.5-flash-lite", "gemini-3.1-flash-lite", "gemini-flash-lite-latest"]
URL = "https://generativelanguage.googleapis.com/v1beta/models/{}:streamGenerateContent?alt=sse"
HEDGE_AFTER = 2.5      # seconds of silence before the next model is raced
DEADLINE = 45          # give up entirely after this long


class Fatal(Exception):
    """An error a retry or another model cannot fix (bad key, quota)."""


def stream(model, data, headers, out, stop):
    """Run one request; push ("text", model, chunk) per chunk, then ("end"|"error"|"fatal", model, msg)."""
    request = Request(URL.format(model), data=data, headers=headers)
    try:
        with urlopen(request, timeout=30) as response:
            for line in response:
                if stop.is_set():
                    return
                if not line.startswith(b"data:"):
                    continue
                event = json.loads(line[5:])
                if event.get("error"):
                    out.put(("error", model, "Gemini returned an error while answering. Press Enter to retry."))
                    return
                candidates = event.get("candidates", [])
                for part in candidates[0].get("content", {}).get("parts", []) if candidates else []:
                    if part.get("text") and not part.get("thought"):
                        out.put(("text", model, part["text"]))
        out.put(("end", model, ""))
    except HTTPError as error:
        if error.code in (400, 401, 403):
            out.put(("fatal", model, "Gemini rejected the request. Check the API key and its Gemini API access."))
        elif error.code == 429:
            out.put(("fatal", model, "Gemini's quota or rate limit was reached. Try again later."))
        else:
            out.put(("error", model, f"Gemini returned HTTP {error.code}. Press Enter to retry."))
    except (URLError, TimeoutError, OSError, ValueError):
        out.put(("error", model, "Gemini's connection was interrupted. Press Enter to retry."))


def main():
    config = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    try:
        key = os.environ.get("GEMINI_API_KEY") or (config / "atelier" / "gemini-api-key").read_text()
    except OSError:
        return fail("Set GEMINI_API_KEY or add an owner-only ~/.config/atelier/gemini-api-key file.")
    if not key.strip():
        return fail("The Gemini API key is empty.")

    data = json.dumps({
        "contents": [{"parts": [{"text": sys.argv[1]}]}],
        "generationConfig": {"thinkingConfig": {"thinkingLevel": "MINIMAL"}},
    }).encode()
    headers = {"x-goog-api-key": key.strip(), "Content-Type": "application/json"}

    out = queue.Queue()
    stop = threading.Event()
    started = 0
    failed = 0
    last_error = "Gemini's connection was interrupted. Press Enter to retry."
    winner = None
    begin = time.monotonic()

    def launch():
        nonlocal started
        threading.Thread(target=stream, args=(MODELS[started], data, headers, out, stop), daemon=True).start()
        started += 1

    launch()
    next_hedge = begin + HEDGE_AFTER
    while time.monotonic() - begin < DEADLINE:
        try:
            kind, model, payload = out.get(timeout=0.1)
        except queue.Empty:
            if winner is None and started < len(MODELS) and time.monotonic() >= next_hedge:
                launch()
                next_hedge = time.monotonic() + HEDGE_AFTER
            continue
        if kind == "text":
            if winner is None:
                winner = model
            if model == winner:
                print(payload, end="", flush=True)
        elif kind == "end":
            if model == winner:
                return 0
            failed += 1
        elif kind == "fatal":
            return fail(payload)
        else:  # error
            if model == winner:
                return fail(payload)
            last_error = payload
            failed += 1
            if winner is None and started < len(MODELS):
                launch()                                  # a failure is a reason to hedge now
            if winner is None and failed >= len(MODELS):
                return fail(last_error)
    stop.set()
    return fail("Gemini took too long to answer. Press Enter to retry.")


def fail(message):
    print("ATELIER_GEMINI: " + message, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
