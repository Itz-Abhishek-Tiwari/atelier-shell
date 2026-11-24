pragma Singleton
import QtQuick

// Shared text formatters: one place for sizes, clocks and "x ago" strings.
QtObject {
    // 1.5e9 → "1.50 GB", 4e6 → "4 MB", 800 → "1 KB"; "0 MB" for nothing
    function bytes(b: real): string {
        if (!b || b <= 0) return "0 MB";
        if (b >= 1e9) return (b / 1e9).toFixed(b < 1e10 ? 2 : 1) + " GB";
        if (b >= 1e6) return Math.round(b / 1e6) + " MB";
        if (b >= 1e3) return Math.round(b / 1e3) + " KB";
        return b + " B";
    }
    // seconds → "3:07" or "1:02:09"
    function clock(s: real): string {
        s = Math.max(0, Math.floor(s || 0));
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), ss = String(s % 60).padStart(2, "0");
        return h > 0 ? h + ":" + String(m).padStart(2, "0") + ":" + ss : m + ":" + ss;
    }
    // epoch milliseconds → "just now" / "5 min ago" / "3 h ago" / "yesterday" / "4 days ago"
    function ago(ms: real): string {
        const m = Math.round((Date.now() - ms) / 60000);
        if (m < 1) return "just now";
        if (m < 60) return m + " min ago";
        const h = Math.round(m / 60);
        if (h < 24) return h + " h ago";
        const d = Math.round(h / 24);
        return d === 1 ? "yesterday" : d + " days ago";
    }
}
