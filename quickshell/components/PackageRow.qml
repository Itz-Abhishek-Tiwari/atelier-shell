import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// One package in a list (Settings → Install & remove, the Software drawer): icon (or a glyph) · name,
// source chip, description, version · Install / Remove. State and actions live in services/Packages.qml.
Item {
    id: row
    property var pkg
    property string title
    property string subtitle
    property string meta
    property string glyph: "󰏖"
    property color glyphTint: Atelier.blue
    property string sourceLabel: ""
    property color sourceTint: Atelier.blue
    property bool isInstalled: false
    property bool first: false

    readonly property string iconUrl: Packages.iconFor(pkg)
    readonly property bool working: Packages.busy === (pkg ? pkg.name : "")
    readonly property bool confirming: Packages.confirmRemove === (pkg ? pkg.name : "")

    Layout.fillWidth: true
    implicitHeight: 64

    Rectangle { visible: !row.first; anchors.top: parent.top; width: parent.width; height: 1; color: Atelier.outline }

    RowLayout {
        anchors.fill: parent
        spacing: 12
        Item {
            implicitWidth: 36; implicitHeight: 36
            IconImage {
                id: appIcon
                anchors.fill: parent
                visible: row.iconUrl !== "" && status === Image.Ready
                source: row.iconUrl
                asynchronous: true
            }
            Rectangle {
                anchors.fill: parent
                visible: !appIcon.visible
                radius: Atelier.radiusSm
                color: Qt.alpha(row.glyphTint, 0.14)
                border.width: 1; border.color: Qt.alpha(row.glyphTint, 0.3)
                Text { anchors.centerIn: parent; text: row.glyph; font.family: Atelier.font; font.pixelSize: Atelier.iconMd; color: row.glyphTint }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: row.title; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; font.weight: Font.DemiBold
                    color: Atelier.text; elide: Text.ElideRight; Layout.maximumWidth: 260 }
                Chip { visible: row.sourceLabel !== ""; text: row.sourceLabel; tint: row.sourceTint; implicitHeight: 20; pad: 7 }
                Text { Layout.fillWidth: true; text: row.meta; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                    color: Atelier.subtext; elide: Text.ElideRight }
            }
            Text { Layout.fillWidth: true; visible: text !== ""; text: row.subtitle
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext1; elide: Text.ElideRight }
        }
        Chip {
            visible: row.working
            icon: "󰆍"; text: "Opened in terminal"; tint: Atelier.peach; implicitHeight: 28
        }
        Chip {
            visible: !row.working && row.isInstalled && row.pkg && !row.pkg.protected
            icon: row.confirming ? "󰆴" : "󰩹"
            text: row.confirming ? "Remove?" : "Remove"
            tint: Atelier.red; interactive: true; implicitHeight: 28
            onClicked: { if (!row.confirming) Packages.askRemove(row.pkg.name); else Packages.act(row.pkg, true); }
        }
        Chip {
            visible: !row.working && row.isInstalled && row.pkg && row.pkg.protected
            icon: "󰌾"; text: "System"; tint: Atelier.subtext; implicitHeight: 28
        }
        Chip {
            visible: !row.working && !row.isInstalled
            icon: "󰇚"; text: "Install"; tint: Atelier.green; interactive: true; implicitHeight: 28
            onClicked: Packages.act(row.pkg, false)
        }
    }
}
