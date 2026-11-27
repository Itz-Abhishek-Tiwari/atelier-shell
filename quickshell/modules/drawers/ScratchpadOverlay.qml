import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config
import qs.services

// Scratchpad: a bottom drawer with one plain-text note, saved as you type (services/Scratchpad.qml).
// Open: Super+Alt+N · IPC `scratchpad toggle|open|close|get|append|clear` · launcher "Scratchpad".
Item {
    id: root
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window

    property bool isLight: Atelier.isLight
    property bool animActive: false
    property double openedAt: 0

    signal closedSignal()

    function toggle() { if (visible && animActive) close(); else open(); }
    function open() {
        visible = true;
        animActive = true;
        openedAt = Date.now();
        focusTimer.restart();
    }
    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }

    Timer { id: focusTimer; interval: 40; onTriggered: { pad.forceActiveFocus(); pad.cursorPosition = pad.length; } }
    Timer { id: closeTimer; interval: Atelier.durClose + 40; onTriggered: if (!root.animActive) root.visible = false }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    EdgeDrawer {
        id: drawer
        edge: "bottom"
        open: root.animActive
        bodyWidth: Math.min(root.width - 160, 640)
        bodyHeight: 380

        MouseArea { anchors.fill: parent }   // clicks inside don't close

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                DrawerTitle {
                    Layout.fillWidth: true
                    icon: "󰎞"; tint: Atelier.yellow; title: "Scratchpad"
                    subtitle: Scratchpad.words === 0 ? "Jot something down" : Scratchpad.words + (Scratchpad.words === 1 ? " word" : " words") + "  ·  saved as you type"
                }
                IconButton { accessibleLabel: "Copy note"; icon: "󰆏"; size: 30; glyphSize: 14; onClicked: Scratchpad.copy() }
                IconButton { accessibleLabel: "Clear note"; icon: "󰩺"; size: 30; glyphSize: 14; onClicked: { Scratchpad.clear(); pad.forceActiveFocus(); } }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Atelier.radiusLg
                color: Atelier.container
                border.width: 1
                border.color: pad.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                Behavior on border.color { CAnim {} }

                Flickable {
                    id: flick
                    anchors.fill: parent
                    anchors.margins: 12
                    clip: true
                    contentWidth: width
                    contentHeight: pad.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    function follow() {
                        const r = pad.cursorRectangle;
                        if (r.y < contentY) contentY = r.y;
                        else if (r.y + r.height > contentY + height) contentY = r.y + r.height - height;
                    }

                    TextEdit {
                        id: pad
                        width: flick.width
                        height: Math.max(implicitHeight, flick.height)
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        color: Atelier.text
                        selectionColor: Qt.alpha(Atelier.accent, 0.4)
                        selectedTextColor: Atelier.text
                        font.family: Atelier.fontUi
                        font.pixelSize: Atelier.fsLg
                        text: Scratchpad.text
                        onTextChanged: Scratchpad.set(text)
                        onCursorRectangleChanged: flick.follow()
                        Keys.onPressed: (e) => {
                            if (e.isAutoRepeat && Date.now() - root.openedAt < 350) { e.accepted = true; return; }
                            if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; }
                        }
                        Text {
                            visible: !pad.text && Scratchpad.loaded
                            text: "Type here. Esc closes, it is saved automatically."
                            font: pad.font; color: Atelier.subtext; opacity: 0.7
                        }
                    }
                }
            }
        }
    }
}
