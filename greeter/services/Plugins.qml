pragma Singleton
import QtQuick
import Quickshell

// Login-screen stand-in: user plugins live in the home folder, which the greeter cannot read,
// so there are none here (PhoneLock asks this for a plugin lock face and gets nothing).
Singleton {
    readonly property var lockStyles: []
    function lockFile(uid) { return ""; }
    function attach(item, entry) {}
    function reportError(pluginId, msg) {}
}
