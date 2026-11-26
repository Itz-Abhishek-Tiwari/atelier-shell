import QtQuick
import Quickshell.Widgets
import qs.config
import qs.services

// Password screens for the phone-inspired styles that have their own look: Hyper, Harmony,
// Oxygen, Material and Dot. (Cupertino keeps PhoneLock's shared glass-pill screen.)
// They sit on the blurred, darkened wallpaper that PhoneLock draws behind every phone style.
Item {
    id: root
    required property var ph
    readonly property real u: ph.u
    readonly property var lr: ph.lockRoot
    readonly property real dur: Atelier.durMedium
    readonly property string who: Atelier.userName
    readonly property string msg: lr.message ? lr.message : ph.capsOn ? "Caps Lock is on" : ph.isPreview ? "Preview · Esc to go back" : "Enter to unlock · Esc to go back"
    readonly property color msgColor: lr.message ? Qt.tint("white", Qt.alpha(Atelier.red, 0.8)) : ph.capsOn ? Qt.tint("white", Qt.alpha(Atelier.yellow, 0.7)) : Qt.rgba(1, 1, 1, 0.75)
    readonly property string greeting: { const h = ph.now.getHours(); return h < 12 ? "Good morning," : h < 18 ? "Good afternoon," : "Good evening,"; }

    Shaker { id: shaker; ph: root.ph }

    Loader {
        anchors.fill: parent
        sourceComponent: ({ hyper: hyperAuth, harmony: harmonyAuth, oxygen: oxygenAuth, material: materialAuth, dot: dotAuth })[root.ph.variant]
    }

    // ═══ Hyper (Xiaomi HyperOS): left-aligned, a big thin name, a squared field ═══
    Component {
        id: hyperAuth
        Item {
            Column {
                x: 0.08 * root.width
                anchors.verticalCenter: parent.verticalCenter
                spacing: 20 * root.u
                Text { text: root.greeting; font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.7; font.weight: Font.Light; color: Qt.rgba(1, 1, 1, 0.8) }
                Text { text: root.who; font.family: ph.display; font.pixelSize: 150 * root.u; font.weight: Font.Thin; font.letterSpacing: -3 * root.u; renderType: Text.CurveRendering; color: "white" }
                Item { width: 1; height: 14 * root.u }
                Item {
                    width: 700 * root.u; height: 92 * root.u
                    transform: Translate { x: shaker.dx }
                    Rectangle {
                        anchors.fill: parent; radius: 26 * root.u
                        color: Qt.rgba(1, 1, 1, 0.14)
                        border.width: Math.max(1, 2 * root.u); border.color: root.lr.message ? Qt.alpha(Atelier.red, 0.9) : Qt.rgba(1, 1, 1, 0.3)
                    }
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 32 * root.u; anchors.verticalCenter: parent.verticalCenter
                        visible: root.lr.buffer.length === 0
                        text: root.lr.checking ? "Checking…" : "Enter password"
                        font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.5; font.weight: Font.Light; color: Qt.rgba(1, 1, 1, 0.6)
                    }
                    Row {
                        anchors.left: parent.left; anchors.leftMargin: 32 * root.u; anchors.verticalCenter: parent.verticalCenter
                        spacing: 12 * root.u
                        Repeater {
                            model: Math.min(root.lr.buffer.length, 20)
                            Rectangle { width: 14 * root.u; height: width; radius: width / 2; color: "white"
                                scale: 0; Component.onCompleted: scale = 1; Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutBack } } }
                        }
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 12 * root.u; anchors.verticalCenter: parent.verticalCenter
                        width: 68 * root.u; height: width; radius: 20 * root.u
                        visible: root.lr.buffer.length > 0 || root.lr.checking
                        color: Atelier.accent
                        Text { anchors.centerIn: parent; text: root.lr.checking ? "󰑐" : "󰁔"; font.family: Atelier.font; font.pixelSize: Atelier.fsXl * ph.ts * 1.8; color: Atelier.crust
                            RotationAnimation on rotation { running: root.lr.checking; loops: Animation.Infinite; from: 0; to: 360; duration: 800 } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.lr.submit() }
                    }
                }
                Text { text: root.msg; font.family: ph.display; font.pixelSize: Atelier.fsLg * ph.ts * 1.1; color: root.msgColor }
            }
            AuthPower { ph: root.ph; x: 0.08 * root.width; anchors.bottom: parent.bottom; anchors.bottomMargin: 0.06 * root.height
                ink: "white"; fill: Qt.rgba(1, 1, 1, 0.14); btnRadius: 18 * root.u; family: ph.display }
        }
    }

    // ═══ Harmony (Huawei HarmonyOS): airy, no box, just a line ═══
    Component {
        id: harmonyAuth
        Item {
            Column {
                anchors.centerIn: parent; anchors.verticalCenterOffset: -30 * root.u
                spacing: 22 * root.u
                ClippingRectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 104 * root.u; height: width; radius: width / 2; color: Qt.rgba(1, 1, 1, 0.14)
                    Image { id: pic; anchors.fill: parent; source: Profile.faceUrl; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 208; sourceSize.height: 208 }
                    Text { anchors.centerIn: parent; visible: pic.status !== Image.Ready; text: root.who.charAt(0).toUpperCase(); font.family: ph.display; font.pixelSize: 44 * root.u; color: "white" }
                }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.who; font.family: ph.display; font.pixelSize: 44 * root.u; font.weight: Font.Light; color: "white" }
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 420 * root.u; height: 64 * root.u
                    transform: Translate { x: shaker.dx }
                    Text {
                        anchors.centerIn: parent; visible: root.lr.buffer.length === 0
                        text: root.lr.checking ? "Checking…" : "Password"
                        font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.4; font.weight: Font.Light; color: Qt.rgba(1, 1, 1, 0.55)
                    }
                    Row {
                        anchors.centerIn: parent; spacing: 16 * root.u
                        Repeater {
                            model: Math.min(root.lr.buffer.length, 16)
                            Rectangle { width: 10 * root.u; height: width; radius: width / 2; color: "white"
                                scale: 0; Component.onCompleted: scale = 1; Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutBack } } }
                        }
                    }
                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: Math.max(1, 2 * root.u)
                        color: root.lr.message ? Atelier.red : Qt.rgba(1, 1, 1, 0.7) }
                }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.msg; font.family: ph.display; font.pixelSize: Atelier.fsLg * ph.ts; font.weight: Font.Light; color: root.msgColor }
            }
            Text {
                visible: root.lr.buffer.length > 0 || root.lr.checking
                anchors.horizontalCenter: parent.horizontalCenter; y: parent.height / 2 + 190 * root.u
                text: root.lr.checking ? "󰑐" : "󰁔"; font.family: Atelier.font; font.pixelSize: Atelier.fsXl * ph.ts * 2.2; color: Qt.rgba(1, 1, 1, 0.9)
                RotationAnimation on rotation { running: root.lr.checking; loops: Animation.Infinite; from: 0; to: 360; duration: 800 }
                MouseArea { anchors.fill: parent; anchors.margins: -14; cursorShape: Qt.PointingHandCursor; onClicked: root.lr.submit() }
            }
            AuthPower { ph: root.ph; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 0.06 * root.height
                ink: "white"; fill: Qt.rgba(1, 1, 1, 0.12); family: ph.display }
        }
    }

    // ═══ Oxygen (OnePlus OxygenOS): a frosted shelf along the bottom, red accent ═══
    Component {
        id: oxygenAuth
        Item {
            readonly property color hot: Settings.lockStyle.oxygenAccent === "theme" ? Atelier.accent : "#eb0029"
            Rectangle {
                id: shelf
                x: 0.04 * root.width; width: 0.92 * root.width; height: 250 * root.u
                anchors.bottom: parent.bottom; anchors.bottomMargin: 0.07 * root.height
                radius: 48 * root.u; color: Qt.rgba(0, 0, 0, 0.42)
                border.width: Math.max(1, 2 * root.u); border.color: Qt.rgba(1, 1, 1, 0.16)
                ClippingRectangle {
                    x: 34 * root.u; anchors.verticalCenter: parent.verticalCenter
                    width: 160 * root.u; height: width; radius: 30 * root.u; color: Qt.rgba(1, 1, 1, 0.12)
                    Image { id: pic; anchors.fill: parent; source: Profile.faceUrl; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 320; sourceSize.height: 320 }
                    Text { anchors.centerIn: parent; visible: pic.status !== Image.Ready; text: root.who.charAt(0).toUpperCase(); font.family: Atelier.font; font.pixelSize: 64 * root.u; color: "white" }
                }
                Column {
                    x: 230 * root.u; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 230 * root.u - 60 * root.u
                    spacing: 18 * root.u
                    Text { text: root.who.toUpperCase(); font.family: Atelier.font; font.pixelSize: Atelier.fsXl * ph.ts * 1.7; font.letterSpacing: 8 * root.u; color: "white" }
                    Item {
                        width: parent.width; height: 74 * root.u
                        transform: Translate { x: shaker.dx }
                        Rectangle { anchors.fill: parent; radius: 16 * root.u; color: Qt.rgba(1, 1, 1, 0.08) }
                        Rectangle { width: 8 * root.u; height: parent.height; radius: 4 * root.u; color: root.lr.message ? Atelier.red : hot }
                        Text {
                            x: 30 * root.u; anchors.verticalCenter: parent.verticalCenter
                            visible: root.lr.buffer.length === 0
                            text: root.lr.checking ? "CHECKING…" : "PASSWORD"
                            font.family: Atelier.font; font.pixelSize: Atelier.fsXl * ph.ts * 1.3; font.letterSpacing: 6 * root.u; color: Qt.rgba(1, 1, 1, 0.5)
                        }
                        Row {
                            x: 30 * root.u; anchors.verticalCenter: parent.verticalCenter; spacing: 12 * root.u
                            Repeater {
                                model: Math.min(root.lr.buffer.length, 24)
                                Rectangle { width: 14 * root.u; height: width; radius: 3 * root.u; color: "white"
                                    scale: 0; Component.onCompleted: scale = 1; Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutBack } } }
                            }
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 8 * root.u; anchors.verticalCenter: parent.verticalCenter
                            width: 58 * root.u; height: width; radius: 14 * root.u; color: hot
                            visible: root.lr.buffer.length > 0 || root.lr.checking
                            Text { anchors.centerIn: parent; text: root.lr.checking ? "󰑐" : "󰁔"; font.family: Atelier.font; font.pixelSize: Atelier.fsXl * ph.ts * 1.6; color: "white"
                                RotationAnimation on rotation { running: root.lr.checking; loops: Animation.Infinite; from: 0; to: 360; duration: 800 } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.lr.submit() }
                        }
                    }
                    Text { text: root.msg.toUpperCase(); font.family: Atelier.font; font.pixelSize: Atelier.fsMd * ph.ts; font.letterSpacing: 4 * root.u; color: root.msgColor }
                }
            }
            AuthPower { ph: root.ph; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: shelf.top; anchors.bottomMargin: 36 * root.u
                ink: "white"; fill: Qt.rgba(0, 0, 0, 0.4); btnRadius: 16 * root.u; family: Atelier.font; upper: true }
        }
    }

    // ═══ Material (Pixel / Material You): a big avatar and a chunky tonal field ═══
    Component {
        id: materialAuth
        Item {
            readonly property color tone: Qt.alpha(Atelier.accent, 0.3)
            Column {
                anchors.centerIn: parent; anchors.verticalCenterOffset: -30 * root.u
                spacing: 24 * root.u
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 190 * root.u; height: width; radius: width / 2; color: tone
                    ClippingRectangle {
                        anchors.centerIn: parent; width: parent.width - 20 * root.u; height: width; radius: width / 2; color: Qt.rgba(1, 1, 1, 0.12)
                        Image { id: pic; anchors.fill: parent; source: Profile.faceUrl; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 380; sourceSize.height: 380 }
                        Text { anchors.centerIn: parent; visible: pic.status !== Image.Ready; text: root.who.charAt(0).toUpperCase(); font.family: ph.display; font.pixelSize: 80 * root.u; color: "white" }
                    }
                }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.who; font.family: ph.display; font.pixelSize: 58 * root.u; font.weight: Font.DemiBold; color: "white" }
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 560 * root.u; height: 92 * root.u
                    transform: Translate { x: shaker.dx }
                    Rectangle { anchors.fill: parent; radius: height / 2; color: tone; border.width: Math.max(2, 3 * root.u); border.color: root.lr.message ? Atelier.red : Qt.alpha(Atelier.accent, 0.7) }
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 38 * root.u; anchors.verticalCenter: parent.verticalCenter
                        visible: root.lr.buffer.length === 0
                        text: root.lr.checking ? "Checking…" : "Password"
                        font.family: ph.display; font.pixelSize: Atelier.fsXl * ph.ts * 1.5; color: Qt.rgba(1, 1, 1, 0.7)
                    }
                    Row {
                        anchors.left: parent.left; anchors.leftMargin: 38 * root.u; anchors.verticalCenter: parent.verticalCenter; spacing: 12 * root.u
                        Repeater {
                            model: Math.min(root.lr.buffer.length, 18)
                            Rectangle { width: 20 * root.u; height: width; radius: width / 2; color: "white"
                                scale: 0; Component.onCompleted: scale = 1; Behavior on scale { NumberAnimation { duration: Atelier.durFast; easing.type: Easing.OutBack } } }
                        }
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 12 * root.u; anchors.verticalCenter: parent.verticalCenter
                        width: 68 * root.u; height: width; radius: width / 2; color: Atelier.accent
                        visible: root.lr.buffer.length > 0 || root.lr.checking
                        Text { anchors.centerIn: parent; text: root.lr.checking ? "󰑐" : "󰁔"; font.family: Atelier.font; font.pixelSize: Atelier.fsXl * ph.ts * 1.8
                            color: Atelier.contrast(Atelier.crust, Atelier.accent) >= Atelier.contrast(Atelier.text, Atelier.accent) ? Atelier.crust : Atelier.text
                            RotationAnimation on rotation { running: root.lr.checking; loops: Animation.Infinite; from: 0; to: 360; duration: 800 } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.lr.submit() }
                    }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: msgText.width + 48 * root.u; height: 46 * root.u; radius: height / 2
                    color: root.lr.message ? Qt.alpha(Atelier.red, 0.3) : Qt.rgba(1, 1, 1, 0.12)
                    Text { id: msgText; anchors.centerIn: parent; text: root.msg; font.family: ph.display; font.pixelSize: Atelier.fsLg * ph.ts; color: "white" }
                }
            }
            AuthPower { ph: root.ph; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 0.06 * root.height
                ink: "white"; fill: tone; btnRadius: 22 * root.u; family: ph.display }
        }
    }

    // ═══ Dot (Nothing OS): dot-matrix, a row of cells that fill as you type ═══
    Component {
        id: dotAuth
        Item {
            readonly property color hot: Atelier.red
            Column {
                anchors.centerIn: parent; anchors.verticalCenterOffset: -20 * root.u
                spacing: 34 * root.u
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.who.toUpperCase(); font.family: Atelier.font; font.pixelSize: Atelier.fsXl * ph.ts * 1.8; font.letterSpacing: 10 * root.u; color: "white" }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.lr.checking ? "CHECKING" : "ENTER PASSCODE"; font.family: Atelier.font; font.pixelSize: Atelier.fsMd * ph.ts; font.letterSpacing: 8 * root.u; color: Qt.rgba(1, 1, 1, 0.55) }
                Row {
                    id: cells
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10 * root.u
                    transform: Translate { x: shaker.dx }
                    Repeater {
                        model: 12
                        Rectangle {
                            id: cell
                            required property int index
                            readonly property bool filled: index < root.lr.buffer.length
                            width: 46 * root.u; height: 60 * root.u
                            color: filled ? (root.lr.message ? hot : "white") : "transparent"
                            border.width: Math.max(1, 2 * root.u); border.color: filled ? "transparent" : (index === root.lr.buffer.length ? hot : Qt.rgba(1, 1, 1, 0.35))
                            Behavior on color { ColorAnimation { duration: Atelier.durFast } }
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.msg.toUpperCase(); font.family: Atelier.font; font.pixelSize: Atelier.fsMd * ph.ts; font.letterSpacing: 5 * root.u
                    color: root.lr.message ? hot : Qt.rgba(1, 1, 1, 0.6)
                }
                // the Enter key as a red dot button
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.lr.buffer.length > 0 || root.lr.checking
                    width: 72 * root.u; height: width; radius: width / 2; color: hot
                    Text { anchors.centerIn: parent; text: root.lr.checking ? "󰑐" : "󰁔"; font.family: Atelier.font; font.pixelSize: Atelier.fsXl * ph.ts * 1.8; color: "white"
                        RotationAnimation on rotation { running: root.lr.checking; loops: Animation.Infinite; from: 0; to: 360; duration: 800 } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.lr.submit() }
                }
            }
            AuthPower { ph: root.ph; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 0.06 * root.height
                ink: "white"; fill: Qt.rgba(1, 1, 1, 0.1); btnRadius: 0; family: Atelier.font; upper: true }
        }
    }
}
