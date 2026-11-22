pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.config

// The shell's own notification daemon (replaces mako).
//  - list:   every notification still tracked (shown in the control center)
//  - popups: the ones currently shown as pop-ups (auto-expire)
//  - dnd:    Do Not Disturb — notifications still land in the list, no pop-ups
Singleton {
    id: root

    readonly property var list: server.trackedNotifications.values.slice().reverse()   // newest first
    readonly property int count: server.trackedNotifications.values.length
    // macOS-style stacks: notifications from the same app with the same title (one chat, one
    // sender) are one card showing the newest, with a count. `groups` = the newest of each.
    readonly property var groups: {
        const seen = {}, out = [];
        for (const n of list) { const k = groupKey(n); if (!seen[k]) { seen[k] = true; out.push(n); } }
        return out;
    }
    function groupKey(n): string {
        if (!n) return "";
        if (!Settings.notifications.stack) return "id:" + n.id;
        const h = n.hints || {};
        return (h["x-kde-display-appname"] || n.appName || "") + "\u0001" + (n.summary || "");
    }
    // every notification in n's stack, newest first
    function groupOf(n): var { const k = groupKey(n); return list.filter(x => groupKey(x) === k); }
    function dismissGroup(n): void { for (const x of groupOf(n)) { hidePopup(x); x.dismiss(); } }
    property var popups: []
    // a card's reply field is open: DrawerHost then takes keyboard focus on demand
    property bool replying: false
    property var times: ({})          // notification id -> arrival time (ms)
    // a clock for "2m ago" labels (cards, "checked 2h ago"): Date.now() alone isn't a binding
    // dependency, so they froze at "now". Half-minute ticks cost nothing.
    property real now: Date.now()
    Timer {
        running: true
        interval: 30000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    function receivedAt(n): real {
        return times[n.id] || Date.now();
    }

    PersistentProperties {
        id: persist
        reloadableId: "atelier-notifs"
        property bool dnd: false
    }
    property alias dnd: persist.dnd

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        actionIconsSupported: true
        imageSupported: true
        inlineReplySupported: true          // e.g. Tether: answer an iPhone message from the card

        extraHints: ["x-canonical-private-synchronous", "x-dunst-stack-tag", "synchronous", "value"]

        onNotification: (n) => {
            const tag = root.tagOf(n);

            // Volume / brightness "notifications" (from scripts, media keys, etc.) go to the
            // OSD slider instead of piling up as separate pop-ups.
            if (/volume|brightness|backlight/i.test(tag)) {
                const v = Number(n.hints && n.hints.value);
                root.osdRequested(/volume/i.test(tag) ? "volume" : "brightness", isNaN(v) ? -1 : v / 100);
                n.dismiss();
                return;
            }

            // Same stack tag = replace the previous one (what mako/dunst do)
            if (tag) {
                for (const old of server.trackedNotifications.values.slice()) {
                    if (old !== n && root.tagOf(old) === tag) {
                        root.hidePopup(old);
                        old.dismiss();
                    }
                }
            }

            n.tracked = true;
            const t = Object.assign({}, root.times);
            t[n.id] = Date.now();
            root.times = t;
            if (!root.dnd || n.urgency === NotificationUrgency.Critical) {
                const k = root.groupKey(n);
                root.popups = [n].concat(root.popups.filter(p => root.groupKey(p) !== k))
                    .slice(0, Math.max(1, Settings.notifications.maxPopups));
            }
        }
    }

    // Asks the OSD (Osd.qml) to show a level; value 0..1, or -1 = read it yourself
    signal osdRequested(string kind, real value)

    function tagOf(n): string {
        const h = n && n.hints ? n.hints : {};
        return String(h["x-canonical-private-synchronous"] || h["x-dunst-stack-tag"] || h["synchronous"] || "");
    }

    // Pop-up lifetime: the app's timeout, or 5s (critical ones stay until dismissed)
    function timeoutFor(n): int {
        if (!n || n.urgency === NotificationUrgency.Critical) return 0;
        return n.expireTimeout > 0 ? Math.min(n.expireTimeout, 15000) : Math.max(1, Settings.notifications.popupSeconds) * 1000;
    }

    function hidePopup(n): void {
        popups = popups.filter(p => p !== n);
    }

    function dismiss(n): void {
        hidePopup(n);
        n.dismiss();
    }

    // take every pop-up off the screen (they stay in the control center's list)
    function hideAllPopups(): void { popups = []; }
    // dismiss everything currently popped up (each one's whole stack)
    function dismissPopups(): void { for (const n of popups.slice()) dismissGroup(n); popups = []; }

    function clearAll(): void {
        popups = [];
        const all = server.trackedNotifications.values.slice();
        for (const n of all) n.dismiss();
    }

    // Default action if the app offers one, otherwise just dismiss
    function activate(n): void {
        const def = n.actions.find(a => a.identifier === "default");
        if (def) def.invoke();
        dismiss(n);
    }

    function iconFor(n): string {
        if (n.image) return n.image;
        if (n.appIcon) return n.appIcon.startsWith("/") || n.appIcon.startsWith("file:") ? n.appIcon : Quickshell.iconPath(n.appIcon, true);
        if (n.desktopEntry) {
            const e = DesktopEntries.byId(n.desktopEntry) || DesktopEntries.heuristicLookup(n.desktopEntry);
            if (e && e.icon) return Quickshell.iconPath(e.icon, true);
        }
        return "";
    }

    // in a sentence: "just now", "5m ago"
    function ago(ms): string { const t = timeAgo(ms); return t === "now" ? "just now" : t + " ago"; }
    function timeAgo(ms): string {
        const s = Math.max(0, Math.floor((root.now - ms) / 1000));
        if (s < 60) return "now";
        if (s < 3600) return Math.floor(s / 60) + "m";
        if (s < 86400) return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }
}
