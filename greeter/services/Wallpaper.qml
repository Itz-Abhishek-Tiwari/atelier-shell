pragma Singleton
import QtQuick
import Quickshell

// Login-screen stand-in: the wallpaper is the copy in the data folder.
Singleton {
    readonly property string current: GreeterData.dataDir + "/wallpaper.jpg"
}
