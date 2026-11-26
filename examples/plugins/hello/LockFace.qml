import QtQuick
import qs.config

// A lock style: `ph` is the lock (set by the shell). Draw the whole screen; ph.auth is true while
// the password prompt is up (PhoneLock still shows its password field over it).
Item {
    property var ph
    Rectangle { anchors.fill: parent; color: Atelier.crust }
    Column {
        anchors.centerIn: parent
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: ph ? ph.hh + ":" + ph.mm : ""
               color: Atelier.accent; font.pixelSize: 160; font.family: Atelier.font }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Hello, " + Atelier.userName
               color: Atelier.text; font.pixelSize: 32; font.family: Atelier.fontUi }
    }
}
