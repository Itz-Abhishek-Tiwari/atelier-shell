import QtQuick

// A sideways shake for a password field when the password was wrong. Bind `dx` to a Translate.
Item {
    id: sh
    required property var ph
    property real dx: 0
    function go() { anim.restart(); }
    Connections {
        target: sh.ph.thumb ? null : sh.ph.lockRoot
        ignoreUnknownSignals: true
        function onFailed() { sh.go(); }
    }
    SequentialAnimation {
        id: anim
        NumberAnimation { target: sh; property: "dx"; to: -20 * sh.ph.u; duration: 60 }
        NumberAnimation { target: sh; property: "dx"; to: 18 * sh.ph.u; duration: 70 }
        NumberAnimation { target: sh; property: "dx"; to: -10 * sh.ph.u; duration: 70 }
        NumberAnimation { target: sh; property: "dx"; to: 6 * sh.ph.u; duration: 60 }
        NumberAnimation { target: sh; property: "dx"; to: 0; duration: 60 }
    }
}
