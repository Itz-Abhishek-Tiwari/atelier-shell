import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

// A fixed-screen surface for drawers and pop-ups. The shell attaches the shared
// content to the current output's host.
//
// The window is click-through except where something is showing:
//   - while an interactive drawer is open/animating: the whole screen (each drawer has its
//     own full-screen click-catcher that closes it on an outside click)
//   - otherwise: only the OSD and notification cards, while they are visible
PanelWindow {
    id: host

    // Set by shell.qml
    property string activeOverlay: ""        // the open interactive drawer ("" = none)
    property bool drawerVisible: false       // any interactive drawer visible (incl. closing)
    property bool popupRequested: false     // a popup can request a map while children are hidden
    property Item osdItem: null              // input areas while no drawer is open
    property Item notifItem: null
    property Item airdropItem: null          // the AirDrop card (AirDropPopup)

    // Open on hover (Caelestia-style). A hover-opened drawer: takes no keyboard unless clicked,
    // lets clicks elsewhere through (only its body is in the mask), and closes shortly after
    // the pointer is neither on it nor on its bar icon (barHover === activeOverlay).
    property bool hoverMode: false
    property bool panelOnly: false            // an open launcher answer leaves the desktop clickable
    property Item hoverBody: null            // the open drawer's body (EdgeDrawer)
    property string barHover: ""             // bar item under the pointer (Waybar.hoverTarget)
    property var barZones: []                // [{name, a, b, c}]: spans ALONG the bar of the hover icons
    property string edgeHover: ""            // drawer whose screen-edge sensor has the pointer (Frame.qml)
    signal hoverLeft()
    signal hoverSwitch(string name, real centerY)   // pointer rests on another hover icon
    signal hoverPin()                                // clicked the open drawer's own icon

    readonly property alias contentItem: holder
    property bool hostingContent: false

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    // re-map after a glass change so Hyprland applies the new blur threshold (Atelier.remapToken)
    property bool remapping: false
    readonly property bool wantsMap: activeOverlay !== "" || popupRequested
    onWantsMapChanged: if (wantsMap) closeHold.stop(); else closeHold.restart()
    visible: hostingContent && !remapping && (wantsMap || closeHold.running)
    Timer { id: closeHold; interval: Math.max(320, Atelier.durClose + 50) }
    Connections { target: Atelier; function onRemapTokenChanged() { host.remapping = true; hostRemap.restart(); } }
    Timer { id: hostRemap; interval: 60; onTriggered: host.remapping = false }

    // Leave the surface unmapped when idle. Its first configure on every output
    // requests the full monitor geometry, so the compositor never keeps an idle size.
    readonly property int scrW: screen ? screen.width : 1920
    readonly property int scrH: screen ? screen.height : 1080

    WlrLayershell.namespace: "quickshell-drawers"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    // Keyboard only while a drawer is open; the control center types only on demand.
    WlrLayershell.keyboardFocus: activeOverlay === "" ? (Notifs.replying ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)
        : (hoverMode || panelOnly || activeOverlay === "controlcenter") ? WlrKeyboardFocus.OnDemand
        : WlrKeyboardFocus.Exclusive

    readonly property bool fullMask: drawerVisible && !hoverMode && !panelOnly
    readonly property bool hoverActive: drawerVisible && hoverMode

    // While a hover-opened drawer shows, THIS window also covers the stretch of the bar that holds
    // the hover icons and tracks the pointer there itself. Handing the pointer back and forth
    // between the bar's window and this one made hover flicker (leave/enter loops), so the drawer
    // closed and reopened. The rest of the bar stays directly clickable.
    readonly property rect zoneRect: {
        if (!hoverActive || barZones.length === 0) return Qt.rect(0, 0, 0, 0);
        let a = 1e9, b = -1e9;
        for (const z of barZones) { a = Math.min(a, z.a); b = Math.max(b, z.b); }
        a -= 4; b += 4;
        const t = Atelier.inset(Atelier.barEdge);
        switch (Atelier.barEdge) {
        case "left":   return Qt.rect(0, a, t, b - a);
        case "right":  return Qt.rect(host.width - t, a, t, b - a);
        case "top":    return Qt.rect(a, 0, b - a, t);
        default:       return Qt.rect(a, host.height - t, b - a, t);
        }
    }
    function zoneAt(along) {
        for (const z of barZones) if (along >= z.a - 2 && along <= z.b + 2) return z;
        return null;
    }

    // The hover-opened drawer's rectangle in window coordinates, with the bar strip cut off.
    readonly property rect hoverRect: {
        const b = hoverBody;
        if (!drawerVisible || (!hoverMode && !panelOnly) || !b) return Qt.rect(0, 0, 0, 0);
        // touch the geometry so the binding re-evaluates when the drawer moves/resizes
        const _deps = [b.x, b.y, b.width, b.height, host.width, host.height, Atelier.barEdge];
        const p = b.mapToItem(holder, 0, 0);
        let x = p.x, y = p.y, w = b.width, h = b.height;
        switch (Atelier.barEdge) {
        case "left":   { const c = Atelier.insetLeft - x; if (c > 0) { x += c; w -= c; } break; }
        case "top":    { const c = Atelier.insetTop - y;  if (c > 0) { y += c; h -= c; } break; }
        case "right":  { const lim = host.width - Atelier.insetRight;   if (x + w > lim) w = lim - x; break; }
        case "bottom": { const lim = host.height - Atelier.insetBottom; if (y + h > lim) h = lim - y; break; }
        }
        return Qt.rect(x, y, Math.max(0, w), Math.max(0, h));
    }
    mask: Region {
        item: host.fullMask ? holder : null
        // the drawer body minus the bar strip, so the bar still gets hover: sliding along it
        // switches straight to the next icon's drawer
        Region {
            x: host.hoverRect.x; y: host.hoverRect.y
            width: host.hoverRect.width; height: host.hoverRect.height
        }
        Region { x: host.zoneRect.x; y: host.zoneRect.y; width: host.zoneRect.width; height: host.zoneRect.height }
        Region { item: host.fullMask ? null : host.osdItem }
        Region { item: host.fullMask ? null : host.notifItem }
        Region { item: host.fullMask ? null : host.airdropItem }
    }

    Item {
        id: holder
        // Keep drawer geometry available while the window is unmapped.
        width: host.scrW
        height: host.scrH

        // In hover mode the mask is just the drawer body (+ OSD/notifications), so this is
        // "pointer is on the drawer". Ancestor HoverHandlers stay hovered over child MouseAreas.
        HoverHandler { id: pointer }
    }

    // The bar's hover icons, while a hover-opened drawer shows (see zoneRect).
    MouseArea {
        id: barStrip
        x: host.zoneRect.x; y: host.zoneRect.y
        width: host.zoneRect.width; height: host.zoneRect.height
        visible: host.hoverActive
        hoverEnabled: true
        cursorShape: zone ? Qt.PointingHandCursor : Qt.ArrowCursor
        // which hover icon is under the pointer: updated on every move (a declarative binding
        // on mouseX/mouseY did not re-evaluate reliably here)
        property var zone: null
        readonly property string zoneName: zone ? zone.name : ""
        function track() {
            const z = containsMouse ? host.zoneAt(Atelier.barVertical ? y + mouseY : x + mouseX) : null;
            const n = z ? z.name : "";
            if (n === zoneName) return;
            zone = z;
            if (n !== "" && n !== host.activeOverlay) switchDwell.restart(); else switchDwell.stop();
        }
        onPositionChanged: track()
        onContainsMouseChanged: track()
        onClicked: {
            if (zoneName === host.activeOverlay) host.hoverPin();               // keep it open
            else if (zone) { host.hoverSwitch(zone.name, zone.c); host.hoverPin(); }
        }
        Timer {
            id: switchDwell
            interval: 140
            onTriggered: if (barStrip.zone && barStrip.zoneName !== host.activeOverlay) host.hoverSwitch(barStrip.zone.name, barStrip.zone.c)
        }
    }

    readonly property bool keepOpen: (pointer.hovered && !barStrip.containsMouse)        // on the drawer
        || barStrip.zoneName === activeOverlay                                         // on its icon
        || (!barStrip.containsMouse && barHover !== "" && barHover === activeOverlay)  // bar still has it
        || (edgeHover !== "" && edgeHover === activeOverlay)                           // on its edge sensor
    onKeepOpenChanged: leaveTimer.restart()
    onHoverModeChanged: leaveTimer.restart()
    Timer {
        id: leaveTimer
        interval: 320            // forgiving: crossing the gap between icon and drawer is fine
        onTriggered: if (host.hoverMode && host.activeOverlay !== "" && !host.keepOpen) host.hoverLeft()
    }

}
