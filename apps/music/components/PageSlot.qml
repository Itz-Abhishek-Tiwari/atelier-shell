import QtQuick

// One page of the app: the page being shown fades and rises in, the one being left fades out.
Item {
    property bool on: false
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    enabled: on
    visible: opacity > 0.01
    opacity: on ? 1 : 0
    y: on ? 0 : 18
    Behavior on opacity { Anim { type: "effects" } }
    Behavior on y { Anim { type: "spatial" } }
}
