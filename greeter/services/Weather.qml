pragma Singleton
import QtQuick
import Quickshell

// Login-screen stand-in for the shell's Weather service (quickshell/services/Weather.qml).
// The lock styles read Weather.line; shell.qml fetches the text once from wttr.in and sets it here.
Singleton {
    property string line: ""
}
