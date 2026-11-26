import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

// Desktop widgets from user plugins (docs/plugins.md): each one is a QML file whose root is an Item,
// shown on the wallpaper in its own click-through-by-default window (Bottom layer, behind windows).
// Manifest keys: hAlign left|center|right, vAlign top|center|bottom, margin (px).
Instantiator {
    model: Settings.widgets.enabled && !Perf.hideWidgets ? Plugins.desktopWidgets : []

    delegate: PanelWindow {
        id: win
        required property var modelData
        // where the user put it (Settings → Plugins → Desktop widgets) wins over the plugin's own manifest
        readonly property var pos: Plugins.layoutOf(modelData.uid)
        readonly property string h: pos.h || modelData.hAlign || "right"
        readonly property string v: pos.v === "middle" ? "center" : (pos.v || (modelData.vAlign === "middle" ? "center" : modelData.vAlign) || "top")
        readonly property int m: pos.margin !== undefined ? pos.margin : (modelData.margin !== undefined ? modelData.margin : 40)
        readonly property int offX: Math.round(pos.x || 0)      // + = right
        readonly property int offY: Math.round(pos.y || 0)      // + = down
        readonly property real sw: win.screen ? win.screen.width : 1920
        readonly property real sh: win.screen ? win.screen.height : 1080

        // a free axis is centred by layer-shell; once nudged it is anchored at the centred spot + the nudge
        readonly property bool aL: h === "left" || (h !== "right" && offX !== 0)
        readonly property bool aT: v === "top" || (v !== "bottom" && offY !== 0)
        anchors { left: aL; right: h === "right"; top: aT; bottom: v === "bottom" }
        margins {
            left: h === "left" ? Atelier.insetLeft + m + offX : aL ? Math.round((sw - implicitWidth) / 2) + offX : 0
            right: Atelier.insetRight + m - offX
            top: v === "top" ? Atelier.insetTop + m + offY : aT ? Math.round((sh - implicitHeight) / 2) + offY : 0
            bottom: Atelier.insetBottom + m - offY
        }
        implicitWidth: Math.max(1, ld.item ? ld.item.implicitWidth : 1)
        implicitHeight: Math.max(1, ld.item ? ld.item.implicitHeight : 1)
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-plugin-" + modelData.uid

        Loader {
            id: ld
            anchors.fill: parent
            source: "file://" + win.modelData.file
            onLoaded: Plugins.attach(item, win.modelData)
            onStatusChanged: if (status === Loader.Error) Plugins.reportError(win.modelData.plugin, win.modelData.id + ": could not load " + win.modelData.file)
        }
    }
}
