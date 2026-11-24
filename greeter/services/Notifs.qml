pragma Singleton
import QtQuick
import Quickshell

// Login-screen stand-in: nobody is signed in yet, so there are no notifications.
Singleton {
    readonly property var list: []
    function iconFor(n) { return ""; }
    function receivedAt(n) { return Date.now(); }
    function timeAgo(ms) { return "now"; }
}
