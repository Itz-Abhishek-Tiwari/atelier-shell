pragma Singleton
import QtQuick
import Quickshell

// Login-screen stand-in for the Depth style's cut-out: depth.png + depth.json in the data
// folder, made for the wallpaper copied next to them (greeter-sync.sh).
Singleton {
    readonly property var d: GreeterData.depth
    readonly property bool ok: !!d.ok
    readonly property string forWall: ok ? Wallpaper.current : ""
    readonly property string cutout: ok ? GreeterData.dataDir + "/depth.png" : ""
    readonly property var profile: d.profile || []
    readonly property string ink: d.ink || ""
    readonly property bool inkDark: !!d.inkDark
}
