import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.config

Item {
    id: calOverlayRoot
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window
    readonly property Item bodyItem: calPopoutContainer   // input area when opened by hover (DrawerHost mask)



    property bool isLight: false
    property bool animActive: false
    property real centerY: 0
    property date viewDate: new Date()
    // refreshed on every open, so "today" and the footer date are right after midnight
    property date today: new Date()
    property int viewYear: viewDate.getFullYear()
    property int viewMonth: viewDate.getMonth()

    // Card geometry
    readonly property int cardWidth: 300
    readonly property int cardHeight: 350
    readonly property int barWidth: 44
    readonly property real cardY: {
        var cy = (centerY > 0) ? centerY : (calOverlayRoot.height / 2);
        return Math.max(12, Math.min(calOverlayRoot.height - cardHeight - 12, cy - cardHeight / 2));
    }

    readonly property string fontMono: Atelier.font
    readonly property color colSurface: Atelier.surface
    readonly property color colBorder: Atelier.outline

    signal closedSignal()

    function toggle(newCenterY) {
        if (visible && animActive) {
            close();
        } else {
            open(newCenterY);
        }
    }

    function open(newCenterY) {
        visible = true;
        animActive = true;
        if (newCenterY !== undefined && newCenterY > 0) {
            calOverlayRoot.centerY = newCenterY;
        } else {
            calOverlayRoot.centerY = height / 2;
        }
        viewDate = new Date();
        today = viewDate;
        viewYear = viewDate.getFullYear();
        viewMonth = viewDate.getMonth();
    }

    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }

    // hide at once, skipping the retract animation (hover-switching to a neighbouring drawer)
    function hideNow() {
        animActive = false;
        closeTimer.stop();
        visible = false;
    }

    Timer {
        id: closeTimer
        interval: Atelier.durClose + 40
        repeat: false
        onTriggered: {
            if (!calOverlayRoot.animActive) {
                calOverlayRoot.visible = false;
            }
        }
    }

    function prevMonth() {
        if (viewMonth === 0) {
            viewMonth = 11;
            viewYear -= 1;
        } else {
            viewMonth -= 1;
        }
    }

    function nextMonth() {
        if (viewMonth === 11) {
            viewMonth = 0;
            viewYear += 1;
        } else {
            viewMonth += 1;
        }
    }

    function resetToday() {
        var now = new Date();
        viewYear = now.getFullYear();
        viewMonth = now.getMonth();
    }

    readonly property var monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    function getDaysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate();
    }

    function getFirstDayOfWeek(year, month) {
        var day = new Date(year, month, 1).getDay();
        return (day === 0) ? 6 : day - 1; // 0 = Mon, 6 = Sun
    }

    // Translucent glass backdrop for dismiss on outside click
    Rectangle {
        anchors.fill: parent
        color: "transparent"

        MouseArea {
            anchors.fill: parent
            onClicked: calOverlayRoot.close()
        }
    }

    // ── Calendar drawer growing out of the bar (Caelestia-style) ───────
    EdgeDrawer {
        id: calPopoutContainer
        edge: Atelier.barEdge        // grows out of wherever the bar is
        open: calOverlayRoot.animActive
        anchorPos: calOverlayRoot.centerY > 0 ? calOverlayRoot.centerY : -1
        bodyWidth: calOverlayRoot.cardWidth
        bodyHeight: calOverlayRoot.cardHeight

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // Header Bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // Circular Month Prev Halo
                Rectangle {
                    width: 28
                    height: 28
                    radius: Atelier.radiusMd
                    color: prevMa.containsMouse ? Atelier.hover : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰅁"
                        font.family: calOverlayRoot.fontMono
                        font.pixelSize: 14
                        color: Atelier.text
                    }

                    MouseArea {
                        id: prevMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: calOverlayRoot.prevMonth()
                    }
                }

                // Month Year Title Capsule
                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    radius: Atelier.radiusMd
                    color: Atelier.container

                    Text {
                        anchors.centerIn: parent
                        text: calOverlayRoot.monthNames[calOverlayRoot.viewMonth] + " " + calOverlayRoot.viewYear
                        font.family: calOverlayRoot.fontMono
                        font.pixelSize: Atelier.fsLg
                        font.bold: true
                        color: Atelier.peach
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: calOverlayRoot.resetToday()
                    }
                }

                // Circular Month Next Halo
                Rectangle {
                    width: 28
                    height: 28
                    radius: Atelier.radiusMd
                    color: nextMa.containsMouse ? Atelier.hover : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰅂"
                        font.family: calOverlayRoot.fontMono
                        font.pixelSize: 14
                        color: Atelier.text
                    }

                    MouseArea {
                        id: nextMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: calOverlayRoot.nextMonth()
                    }
                }
            }

            // Weekday Headers
            Row {
                Layout.fillWidth: true
                spacing: 0

                Repeater {
                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    Item {
                        width: (calPopoutContainer.bodyWidth - 28) / 7
                        height: 20

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.family: calOverlayRoot.fontMono
                            font.pixelSize: Atelier.fsMicro
                            font.bold: true
                            color: calOverlayRoot.isLight ? Atelier.overlay1 : Atelier.subtext
                        }
                    }
                }
            }

            // Calendar Grid Days
            GridLayout {
                id: calGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                rowSpacing: 3
                columnSpacing: 0

                readonly property int daysInMonth: calOverlayRoot.getDaysInMonth(calOverlayRoot.viewYear, calOverlayRoot.viewMonth)
                readonly property int firstDay: calOverlayRoot.getFirstDayOfWeek(calOverlayRoot.viewYear, calOverlayRoot.viewMonth)
                readonly property date today: calOverlayRoot.today
                readonly property bool isCurrentMonth: today.getFullYear() === calOverlayRoot.viewYear && today.getMonth() === calOverlayRoot.viewMonth

                Repeater {
                    model: 42

                    Rectangle {
                        id: dayCell
                        Layout.preferredWidth: (calPopoutContainer.bodyWidth - 28) / 7
                        Layout.preferredHeight: 32
                        radius: Atelier.radiusMd

                        readonly property int dayNum: index - calGrid.firstDay + 1
                        readonly property bool isValidDay: dayNum > 0 && dayNum <= calGrid.daysInMonth
                        readonly property bool isToday: calGrid.isCurrentMonth && dayNum === calGrid.today.getDate()
                        readonly property bool isHovered: dayMa.containsMouse && isValidDay

                        color: isToday 
                            ? (Atelier.peach)
                            : (isHovered ? Atelier.hover : "transparent")

                        Text {
                            anchors.centerIn: parent
                            visible: dayCell.isValidDay
                            text: dayCell.dayNum
                            font.family: calOverlayRoot.fontMono
                            font.pixelSize: Atelier.fsSm
                            font.bold: dayCell.isToday
                            color: dayCell.isToday 
                                ? Atelier.crust 
                                : (dayCell.isHovered 
                                    ? (calOverlayRoot.isLight ? Atelier.blue : Atelier.sky) 
                                    : (Atelier.text))
                        }

                        MouseArea {
                            id: dayMa
                            anchors.fill: parent
                            hoverEnabled: dayCell.isValidDay
                            enabled: dayCell.isValidDay
                        }
                    }
                }
            }

            // Today Date Capsule
            Rectangle {
                Layout.fillWidth: true
                height: 28
                radius: Atelier.radiusMd
                color: Atelier.container

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "󰸗"
                        font.family: calOverlayRoot.fontMono
                        font.pixelSize: Atelier.fsMd
                        color: calOverlayRoot.isLight ? Atelier.blue : Atelier.sky
                    }

                    Text {
                        text: Qt.formatDateTime(calOverlayRoot.today, "dddd, MMMM d, yyyy")
                        font.family: calOverlayRoot.fontMono
                        font.pixelSize: Atelier.fsMicro
                        font.bold: true
                        color: Atelier.text
                    }
                }
            }
        }
}
}
