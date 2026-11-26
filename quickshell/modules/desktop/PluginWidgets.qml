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
        readonly property string h: modelData.hAlign || "right"
        readonly property string v: modelData.vAlign || "top"
        readonly property int m: modelData.margin !== undefined ? modelData.margin : 40

        anchors { left: h === "left"; right: h === "right"; top: v === "top"; bottom: v === "bottom" }
        margins { left: Atelier.insetLeft + m; right: Atelier.insetRight + m; top: Atelier.insetTop + m; bottom: Atelier.insetBottom + m }
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
