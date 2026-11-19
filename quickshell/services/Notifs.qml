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
    property var popups: []
    property var times: ({})          // notification id -> arrival time (ms)

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
            if (!root.dnd || n.urgency === NotificationUrgency.Critical)
                root.popups = [n].concat(root.popups).slice(0, Math.max(1, Settings.notifications.maxPopups));
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

    function timeAgo(ms): string {
        const s = Math.max(0, Math.floor((Date.now() - ms) / 1000));
        if (s < 60) return "now";
        if (s < 3600) return Math.floor(s / 60) + "m";
        if (s < 86400) return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }
}
