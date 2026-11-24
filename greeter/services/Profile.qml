pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Login-screen stand-in: the avatar of the person picked on the login screen
// (faces/<user> in the data folder, else AccountsService's icon).
Singleton {
    id: root
    property string faceUrl: ""
    readonly property string user: GreeterData.user
    onUserChanged: { if (user) probe.running = true; else faceUrl = ""; }
    Process {
        id: probe
        command: ["sh", "-c", 'for f in "$1/faces/$2" "/var/lib/AccountsService/icons/$2"; do [ -f "$f" ] && [ -r "$f" ] && { echo "$f"; exit; }; done', "sh",
                  GreeterData.dataDir, root.user]
        stdout: StdioCollector { onStreamFinished: root.faceUrl = text.trim() ? "file://" + text.trim() : "" }
    }
}
