"""Stream a plain-text Gemini answer for Atelier's launcher."""

import json
import os
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def main():
    config = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    try:
        key = os.environ.get("GEMINI_API_KEY") or (config / "atelier" / "gemini-api-key").read_text()
    except OSError:
        return fail("Set GEMINI_API_KEY or add an owner-only ~/.config/atelier/gemini-api-key file.")
    if not key.strip():
        return fail("The Gemini API key is empty.")

    body = {
        "contents": [{"parts": [{"text": sys.argv[1]}]}],
        "generationConfig": {"thinkingConfig": {"thinkingLevel": "MINIMAL"}},
    }
    request = Request(
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:streamGenerateContent?alt=sse",
        data=json.dumps(body).encode(),
        headers={"x-goog-api-key": key.strip(), "Content-Type": "application/json"},
    )
    try:
        with urlopen(request, timeout=30) as response:
            for line in response:
                if not line.startswith(b"data:"):
                    continue
                event = json.loads(line[5:])
                if event.get("error"):
                    return fail("Gemini returned an error while answering. Press Enter to retry.")
                candidates = event.get("candidates", [])
                if candidates:
                    for part in candidates[0].get("content", {}).get("parts", []):
                        if not part.get("thought"):
                            print(part.get("text", ""), end="", flush=True)
    except HTTPError as error:
        if error.code in (400, 401, 403):
            return fail("Gemini rejected the request. Check the API key and its Gemini API access.")
        if error.code == 429:
            return fail("Gemini's quota or rate limit was reached. Try again later.")
        return fail(f"Gemini returned HTTP {error.code}. Press Enter to retry.")
    except (URLError, TimeoutError, ValueError):
        return fail("Gemini's connection was interrupted. Press Enter to retry.")
    return 0


def fail(message):
    print("ATELIER_GEMINI: " + message, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
