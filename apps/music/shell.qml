import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.components
import qs.config
import qs.services
import qs.views

// Atelier Music: a YouTube Music player in the shell's design, run as its own Quickshell
// instance (`qs -n -p apps/music`, or the `atelier-music` launcher / Super+Alt+Y).
// The UI is only a client: search, the queue and playback live in backend/ytmd.py, so music
// keeps playing after the window closes, and the media keys / the shell's Music drawer control
// it over MPRIS (mpv-mpris).
//
// Song menu: right-click or ⋮ on any song (play next, add to queue / playlist, like, download).
// Keys: Space play/pause · Ctrl+F or / search · Ctrl+L lyrics · Ctrl+Q queue · Ctrl+H home ·
//       Ctrl+←/→ previous/next · F11 fullscreen player · Esc back (leaves fullscreen first)
ShellRoot {
    id: app

    property string page: "home"     // home | search | library | offline | queue | now
    property bool fullscreen: false
    // sidebar: an icon rail by default; the toggle opens it (remembered in ui.json), and narrow
    // windows (< 1000 px) always get the rail
    property bool sidebarOpen: false
    readonly property bool collapsed: !sidebarOpen || win.width < 1000
    property var userCollapsed: null     // kept for the toggle below (writes sidebarOpen)
    onUserCollapsedChanged: if (userCollapsed !== null) { sidebarOpen = !userCollapsed; uiState.setText(JSON.stringify({ sidebarOpen: sidebarOpen })); }
    FileView {
        id: uiState
        path: Quickshell.statePath("ui.json")
        printErrors: false
        onLoaded: { try { app.sidebarOpen = !!JSON.parse(text()).sidebarOpen; } catch (e) {} }
    }
    // Is the window actually on screen? (Hyprland: its workspace is the one showing on its
    // monitor.) Off screen, nothing visual ticks: no visualizer, no clock, no backdrop drift.
    readonly property var toplevel: Hyprland.toplevels.values.find(t => t.title && t.title.endsWith("Atelier Music")) ?? null
    readonly property bool onScreen: toplevel === null || !toplevel.workspace || toplevel.workspace.active
    Binding { target: Music; property: "uiVisible"; value: app.onScreen }
    // the visualizer runs only while it is on screen
    Binding { target: Cava; property: "active"; value: Music.playing && app.onScreen && (app.page === "now" || app.fullscreen) }

    function go(p) {
        if (fullscreen && p !== "fullscreen") setFullscreen(false);
        page = p;
        if (p === "search") Qt.callLater(() => searchView.focusInput());
        else keys.forceActiveFocus();
    }
    function setFullscreen(on) {
        fullscreen = on;
        win.fullscreen = on;
        keys.forceActiveFocus();
    }
    Binding { target: Music; property: "wantLyrics"; value: app.page === "now" || app.fullscreen }

    FloatingWindow {
        id: win
        title: Music.current ? Music.current.title + " · Atelier Music" : "Atelier Music"
        implicitWidth: 1180
        implicitHeight: 760
        minimumSize: Qt.size(820, 560)
        color: "transparent"                  // the glass below; Hyprland blurs what's behind
        onVisibleChanged: if (!visible) Qt.quit()
        onFullscreenChanged: if (!fullscreen && app.fullscreen) app.fullscreen = false   // left via the compositor

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: (e) => {
                const ctrl = e.modifiers & Qt.ControlModifier;
                if (e.key === Qt.Key_Space && !ctrl) { Music.toggle(); e.accepted = true; }
                else if ((ctrl && e.key === Qt.Key_F) || e.key === Qt.Key_Slash) { app.go("search"); e.accepted = true; }
                else if (ctrl && e.key === Qt.Key_L) { app.go(app.page === "now" ? "home" : "now"); e.accepted = true; }
                else if (ctrl && e.key === Qt.Key_Q) { app.go("queue"); e.accepted = true; }
                else if (ctrl && e.key === Qt.Key_H) { app.go("home"); e.accepted = true; }
                else if (ctrl && e.key === Qt.Key_Right) { Music.next(); e.accepted = true; }
                else if (ctrl && e.key === Qt.Key_Left) { Music.prev(); e.accepted = true; }
                else if (e.key === Qt.Key_F11) { app.setFullscreen(!app.fullscreen); e.accepted = true; }
                else if (e.key === Qt.Key_Escape) { if (app.fullscreen) app.setFullscreen(false); else app.go("home"); e.accepted = true; }
            }
        }
        Shortcut { sequences: ["Ctrl+F"]; onActivated: app.go("search") }
        Shortcut { sequences: ["Ctrl+L"]; onActivated: app.go(app.page === "now" ? "home" : "now") }
        Shortcut { sequences: ["Escape"]; enabled: app.page === "search" && !app.fullscreen; onActivated: app.go("home") }
        Shortcut { sequences: ["F11"]; onActivated: app.setFullscreen(!app.fullscreen) }

        // the shell's glass: same opacity and tone as the bar and drawers (Settings → Appearance)
        Rectangle { anchors.fill: parent; color: Atelier.surface }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                // ══ Sidebar (collapses to an icon rail; automatic below 1000 px, the toggle overrides) ══
                Rectangle {
                    id: sidebar
                    readonly property bool rail: app.collapsed
                    Layout.preferredWidth: rail ? 80 : 224
                    Layout.fillHeight: true
                    // an inset panel, like Settings' sidebar
                    color: Atelier.panel
                    radius: Atelier.panelRadius
                    border.width: 1
                    border.color: Atelier.outline
                    z: 2                                  // the rail's tooltips draw over the pages
                    Behavior on Layout.preferredWidth { Anim { type: "spatial" } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: sidebar.rail ? 8 : 12
                        anchors.topMargin: 14
                        spacing: 2
                        Behavior on anchors.margins { Anim { type: "spatial" } }

                        // title + collapse toggle
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 18
                            spacing: 10
                            Rectangle {
                                visible: !sidebar.rail
                                implicitWidth: 36; implicitHeight: 36; radius: Atelier.radiusMd
                                color: Qt.alpha(Atelier.accent, 0.14)
                                border.width: 1
                                border.color: Qt.alpha(Atelier.accent, 0.35)
                                SvgIcon { anchors.centerIn: parent; name: "now"; size: 19; color: Atelier.accent }
                            }
                            ColumnLayout {
                                visible: !sidebar.rail
                                Layout.fillWidth: true
                                spacing: 0
                                Text { text: "Music"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsXl; font.weight: Font.Bold; color: Atelier.text }
                                Text { text: "YouTube Music"; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.subtext }
                            }
                            IconBtn {
                                Layout.alignment: sidebar.rail ? Qt.AlignHCenter : Qt.AlignRight
                                Layout.leftMargin: sidebar.rail ? 4 : 0
                                icon: sidebar.rail ? "menu" : "menu_open"
                                size: 44; iconSize: 22
                                onClicked: app.userCollapsed = !app.collapsed
                            }
                        }

                        NavItem { page: "home"; icon: "home"; label: "Home"; hint: "Ctrl+H" }
                        NavItem { page: "search"; icon: "search"; label: "Search"; hint: "Ctrl+F" }
                        NavItem { page: "library"; icon: "library"; label: "Library"; hint: Music.liked.length > 0 ? String(Music.liked.length) : "" }
                        NavItem { page: "offline"; icon: "offline"; label: "Offline"; alert: Music.online && !Music.netOnline; hint: Music.offlineTracks.length > 0 ? String(Music.offlineTracks.length) : "" }
                        NavItem { page: "queue"; icon: "queue"; label: "Queue"; hint: Music.queue.length > 0 ? String(Math.max(0, Music.queue.length - Music.index - 1)) : "" }
                        NavItem { page: "now"; icon: "lyrics"; label: "Now playing"; railLabel: "Playing"; hint: "Ctrl+L" }

                        Item { Layout.fillHeight: true }

                        // no internet: saved songs still play (the rail shows a dot on Offline instead)
                        Rectangle {
                            visible: Music.online && !Music.netOnline && !sidebar.rail
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            implicitHeight: 34
                            radius: 17
                            color: Qt.alpha(Atelier.peach, 0.14)
                            Text {
                                anchors.centerIn: parent
                                text: sidebar.rail ? "󰖪" : "󰖪  Offline"
                                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; font.weight: Font.DemiBold
                                color: Atelier.peach
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.go("offline") }
                        }
                        Text {
                            visible: (!Music.online || Music.error !== "") && !sidebar.rail
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            wrapMode: Text.WordWrap
                            text: Music.error !== "" ? "󰀦  " + Music.error : "Connecting…"
                            font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm
                            color: Music.error !== "" ? Atelier.red : Atelier.subtext
                            Behavior on color { CAnim {} }
                        }
                    }
                }

                // ══ Pages: the new one fades and rises in, the old one fades out ══
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    PageSlot { on: app.page === "home"; HomeView { anchors.fill: parent; onSearchRequested: app.go("search") } }
                    PageSlot { on: app.page === "search"; SearchView { id: searchView; anchors.fill: parent } }
                    PageSlot { on: app.page === "library"; LibraryView { anchors.fill: parent } }
                    PageSlot { on: app.page === "offline"; OfflineView { anchors.fill: parent } }
                    PageSlot { on: app.page === "queue"; QueueView { anchors.fill: parent } }
                    PageSlot { on: app.page === "now"; NowPlayingView { anchors.fill: parent; active: app.page === "now"; onFullscreenRequested: app.setFullscreen(true) } }
                }
            }

            // the mini player: hidden on Now playing, which has the full controls
            PlayerBar {
                Layout.fillWidth: true
                Layout.preferredHeight: app.page === "now" ? 0 : implicitHeight
                clip: true
                opacity: app.page === "now" ? 0 : 1
                Behavior on Layout.preferredHeight { Anim { type: "emphasizedDecel"; duration: 420 } }
                Behavior on opacity { Anim { type: "effects" } }
                page: app.page
                onNavigate: (p) => app.go(p)
                onFullscreenRequested: app.setFullscreen(true)
            }
        }

        // messages from the daemon (offline skips, failed downloads)
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 104
            visible: Music.notice !== "" && !app.fullscreen
            width: Math.min(parent.width - 80, noticeText.implicitWidth + 40)
            height: 40
            radius: 20
            color: Atelier.surface0
            border.width: 1
            border.color: Atelier.outline
            Text {
                id: noticeText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.parent.width - 120)
                elide: Text.ElideRight
                text: Music.notice
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd
                color: Atelier.text
            }
        }

        FullscreenView {
            anchors.fill: parent
            visible: app.fullscreen
            onExitRequested: app.setFullscreen(false)
        }

        // the song menu (right-click / ⋮ anywhere), above everything
        TrackMenu { z: 100 }
    }

    // `qs -p apps/music ipc call music <fn>`
    IpcHandler {
        target: "music"
        function toggle(): void { Music.toggle(); }
        function next(): void { Music.next(); }
        function prev(): void { Music.prev(); }
        function search(q: string): void { app.go("search"); Music.search(q); }
        function page(name: string): void { if (name === "fullscreen") app.setFullscreen(true); else app.go(name || "home"); }
    }

    component NavItem: Item {
        id: nav
        property string page
        property string icon
        property string label
        property string railLabel: label
        property string hint: ""
        property bool alert: false           // a small dot on the icon (e.g. offline)
        readonly property bool on: app.page === page
        readonly property bool rail: app.collapsed
        Layout.fillWidth: true
        implicitHeight: rail ? 62 : 38
        Behavior on implicitHeight { Anim { type: "spatial" } }

        // ── expanded: Settings' rows (faint accent tint + accent icon when active) ──
        Rectangle {
            anchors.fill: parent
            visible: !nav.rail
            radius: 9
            color: nav.on ? Qt.alpha(Atelier.accent, 0.16) : "transparent"
            Behavior on color { CAnim {} }
            StateLayer { mouseArea: navMa; radius: 9 }
            SvgIcon {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                name: nav.icon; size: 19
                color: nav.on ? Atelier.accent : Atelier.subtext1
                Behavior on color { CAnim {} }
            }
            Text {
                x: 42
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 42 - hintText.width - 14
                elide: Text.ElideRight
                text: nav.label
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg
                font.weight: nav.on ? Font.DemiBold : Font.Normal
                color: nav.on ? Atelier.text : Atelier.subtext1
                Behavior on color { CAnim {} }
            }
            Text {
                id: hintText
                anchors.right: parent.right; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: nav.hint !== "" && (navMa.containsMouse || nav.page === "queue" || nav.page === "offline")
                text: nav.hint
                font.family: Atelier.font; font.pixelSize: Atelier.fsMicro
                color: Atelier.subtext
            }
        }

        // ── rail: Material 3 navigation rail (pill indicator behind the icon, label below) ──
        Item {
            anchors.fill: parent
            visible: nav.rail
            Rectangle {
                id: pill
                anchors.horizontalCenter: parent.horizontalCenter
                y: 6
                height: 32
                radius: 16
                width: nav.on ? 54 : (navMa.containsMouse ? 54 : 36)
                color: nav.on ? Qt.alpha(Atelier.accent, 0.2) : (navMa.containsMouse ? Atelier.containerHigh : "transparent")
                Behavior on width { Anim { type: "fastSpatial" } }
                Behavior on color { CAnim {} }
                SvgIcon {
                    anchors.centerIn: parent
                    name: nav.icon; size: 20
                    color: nav.on ? Atelier.accent : Atelier.subtext1
                    Behavior on color { CAnim {} }
                }
                Rectangle {
                    visible: nav.alert
                    anchors.right: parent.right; anchors.top: parent.top
                    anchors.rightMargin: nav.on ? 10 : 4; anchors.topMargin: 3
                    width: 7; height: 7; radius: 3.5
                    color: Atelier.peach
                    border.width: 1.5; border.color: Atelier.mantle
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: pill.bottom; anchors.topMargin: 4
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: nav.railLabel
                font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMicro
                font.weight: nav.on ? Font.DemiBold : Font.Medium
                color: nav.on ? Atelier.text : Atelier.subtext
                Behavior on color { CAnim {} }
            }
        }
        MouseArea { id: navMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: app.go(nav.page) }
    }

}
