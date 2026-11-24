import QtQuick
import qs.config

// A drawer that only exists while it is in use.
//
// Every drawer used to be built at startup and kept forever (~30 overlays, several thousand
// QML objects, their images and models), which is most of the shell's memory. Wrapped in a
// LazyDrawer it is built the first time it opens and destroyed `keepAlive` ms after it closes.
//
//   LazyDrawer {
//       id: wifiOverlay
//       sourceComponent: Component { WifiOverlay { onClosedSignal: ... } }
//   }
//   wifiOverlay.open(y)              forwards to the drawer, building it first if needed
//   wifiOverlay.call("setTab", "x")  any other function
//   wifiOverlay.set("tab", "x")      a property
//   wifiOverlay.shown                the drawer is on screen (incl. its closing animation)
//
// persistent: built once (in the background, see warm) and never destroyed. For drawers that
//             must open instantly (launcher, switcher) or hold state across opens (media).
// hold:       keep it alive while true (e.g. a sleep timer is running inside it).
// prefetch(): build it in the background now (async), e.g. when the pointer reaches its icon.
Loader {
    id: root

    property int keepAlive: 180000
    property bool persistent: false
    property bool hold: false
    // build in the background this many ms after the shell starts (persistent drawers; -1 = no)
    property int warm: persistent ? 6000 : -1

    readonly property bool shown: item !== null && item.visible
    readonly property Item bodyItem: item && item.bodyItem !== undefined ? item.bodyItem : null

    anchors.fill: parent
    active: false

    // the drawer, built now if necessary (synchronously, finishing a background build)
    function ensure() {
        unload.stop();
        if (!active) { asynchronous = false; active = true; }
        else if (status === Loader.Loading) asynchronous = false;   // completes it right away
        return item;
    }
    function prefetch() {
        unload.stop();
        if (!active) { asynchronous = true; active = true; }
    }
    function call(fn) {
        const it = ensure();
        if (!it || typeof it[fn] !== "function") {
            console.warn("LazyDrawer: no function", fn, "on", it);
            return undefined;
        }
        return it[fn].apply(it, Array.prototype.slice.call(arguments, 1));
    }
    function set(prop, value) { const it = ensure(); if (it) it[prop] = value; }

    function open() { const it = ensure(); return it ? it.open.apply(it, arguments) : undefined; }
    // closing never builds anything
    function close() { if (item) item.close(); }
    function hideNow() { if (item && typeof item.hideNow === "function") item.hideNow(); }

    // ── lifetime ─────────────────────────────────────────────────────────────
    Timer {
        id: unload
        interval: root.keepAlive
        onTriggered: {
            if (root.persistent || root.hold || root.shown) return;
            root.active = false;
        }
    }
    function _scheduleUnload() {
        if (!root.persistent && !root.hold && root.keepAlive > 0 && !root.shown) unload.restart();
    }
    onShownChanged: if (shown) unload.stop(); else _scheduleUnload()
    onHoldChanged: if (!hold) _scheduleUnload()
    // a prefetched drawer that never opened is dropped again too
    onLoaded: if (!shown) _scheduleUnload()

    Timer {
        interval: Math.max(0, root.warm)
        running: root.warm >= 0
        onTriggered: root.prefetch()
    }
}
