import QtQuick
import qs.components
import qs.config
import qs.services

// Terminal: a full-screen terminal. A few "commands" at the top, the time as big block letters,
// and a tmux-style status bar along the bottom. Draws the whole screen.
Item {
    id: root
    required property var ph
    readonly property real u: ph.u
    readonly property string mono: Atelier.font
    readonly property string who: Atelier.userName.toLowerCase() + "@atelier"
    readonly property bool a: ph.auth
    readonly property var lr: ph.lockRoot
    readonly property real dur: Atelier.durMedium
    property bool cursorOn: true

    Timer {
        interval: 530; repeat: true; running: !ph.thumb && ph.lockRoot.active
        onTriggered: root.cursorOn = !root.cursorOn
    }

    // 5 x 7 pixel font for the clock; two pixel rows are packed into one text line with half blocks
    readonly property var glyph: ({
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
        ":": [".", ".", "#", ".", "#", ".", "."]
    })
    readonly property string clockText: {
        const str = ph.hh + ":" + ph.mm;
        const rows = ["", "", "", "", "", "", ""];
        for (let i = 0; i < str.length; i++)
            for (let r = 0; r < 7; r++) rows[r] += (i ? "." : "") + glyph[str[i]][r];
        const lines = [];
        for (let l = 0; l < 4; l++) {
            let line = "";
            for (let c = 0; c < rows[0].length; c++) {
                const top = rows[2 * l][c] === "#";
                const bot = 2 * l + 1 < 7 && rows[2 * l + 1][c] === "#";
                line += top && bot ? "█" : top ? "▀" : bot ? "▄" : " ";
            }
            lines.push(line);
        }
        return lines.join("\n");
    }

    Shaker { id: shaker; ph: root.ph }

    Rectangle { anchors.fill: parent; color: Atelier.crust }

    // faint scanlines
    Repeater {
        model: Math.max(0, Math.ceil(root.height / Math.max(1, 6 * root.u)))
        Rectangle { required property int index; y: index * 6 * root.u; width: root.width; height: Math.max(1, root.u); color: Qt.alpha(Atelier.text, 0.025) }
    }

    // the "session" at the top
    Column {
        x: 0.07 * root.width; y: 0.08 * root.height
        spacing: 14 * root.u
        Row {
            Text { text: root.who; font.family: root.mono; font.pixelSize: 30 * root.u; font.bold: true; color: Atelier.green }
            Text { text: ":~$ "; font.family: root.mono; font.pixelSize: 30 * root.u; color: Atelier.blue }
            Text { text: "lock --show"; font.family: root.mono; font.pixelSize: 30 * root.u; color: Atelier.text }
        }
        Text {
            text: Qt.formatDate(ph.now, "dddd, d MMMM yyyy") + (ph.ampm ? "   " + ph.ampm : "")
            font.family: root.mono; font.pixelSize: 30 * root.u; color: Qt.alpha(Atelier.text, 0.75)
        }
        Text {
            visible: ph.temp !== ""
            text: "weather: " + ph.temp + (ph.condition ? "  " + ph.condition : "")
            font.family: root.mono; font.pixelSize: 30 * root.u; color: Qt.alpha(Atelier.text, 0.75)
        }
    }

    // the clock, in block letters
    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 0.02 * root.height
        text: root.clockText
        textFormat: Text.PlainText
        opacity: root.a ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: root.dur } }
        font.family: root.mono; font.pixelSize: 98 * root.u
        lineHeight: 0.86; lineHeightMode: Text.ProportionalHeight
        color: Atelier.green
    }

    // prompt
    Row {
        opacity: root.a ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: root.dur } }
        x: 0.07 * root.width
        anchors.bottom: statusBar.top; anchors.bottomMargin: 0.06 * root.height
        Text { text: root.who; font.family: root.mono; font.pixelSize: 30 * root.u; font.bold: true; color: Atelier.green }
        Text { text: ":~$ "; font.family: root.mono; font.pixelSize: 30 * root.u; color: Atelier.blue }
        Text { text: "sudo unlock "; font.family: root.mono; font.pixelSize: 30 * root.u; color: Atelier.text }
        Text { text: "▌"; opacity: root.cursorOn ? 1 : 0; font.family: root.mono; font.pixelSize: 30 * root.u; color: Atelier.text }
    }

    // ── the password screen: a real sudo prompt ──
    Column {
        x: 0.07 * root.width
        anchors.verticalCenter: parent.verticalCenter
        spacing: 22 * root.u
        opacity: root.a ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.dur } }
        Text { text: "authenticating " + Atelier.userName.toLowerCase() + " via PAM"; font.family: root.mono; font.pixelSize: Atelier.fsXl * ph.ts * 1.5; color: Qt.alpha(Atelier.text, 0.5) }
        Row {
            transform: Translate { x: shaker.dx }
            Text { text: "[sudo] password for " + Atelier.userName.toLowerCase() + ": "; font.family: root.mono; font.pixelSize: Atelier.fsXl * ph.ts * 2; color: Atelier.text }
            Text { text: "*".repeat(Math.min(root.lr.buffer.length, 40)); font.family: root.mono; font.pixelSize: Atelier.fsXl * ph.ts * 2; color: Atelier.green }
            Text { text: "▌"; opacity: root.cursorOn && !root.lr.checking ? 1 : 0; font.family: root.mono; font.pixelSize: Atelier.fsXl * ph.ts * 2; color: Atelier.text }
        }
        Text {
            visible: text !== ""
            text: root.lr.checking ? "checking..." : root.lr.message ? "Sorry, try again.  (" + root.lr.message + ")" : ph.capsOn ? "warning: Caps Lock is on" : ""
            font.family: root.mono; font.pixelSize: Atelier.fsXl * ph.ts * 1.7
            color: root.lr.message ? Atelier.red : root.lr.checking ? Atelier.accent : Atelier.yellow
            Behavior on color { CAnim {} }
        }
        Text {
            text: ph.isPreview ? "# preview: esc to go back" : "# enter to submit, esc to cancel"
            font.family: root.mono; font.pixelSize: Atelier.fsLg * ph.ts * 1.2; color: Qt.alpha(Atelier.text, 0.4)
        }
    }
    AuthPower {
        ph: root.ph
        anchors.right: parent.right; anchors.rightMargin: 0.07 * root.width
        anchors.bottom: statusBar.top; anchors.bottomMargin: 0.05 * root.height
        opacity: root.a ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.dur } }
        ink: Atelier.green; fill: Qt.alpha(Atelier.green, 0.1); btnRadius: 0; family: root.mono
    }

    // status bar
    Rectangle {
        id: statusBar
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 52 * root.u
        color: Atelier.mantle
        Row {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                width: seg1.width + 36 * root.u; height: statusBar.height; color: Atelier.green
                Text { id: seg1; anchors.centerIn: parent; text: "[0] zsh*"; font.family: root.mono; font.pixelSize: Atelier.iconLg * root.u; font.bold: true; color: Atelier.crust }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; leftPadding: 22 * root.u; text: "locked  ·  type to unlock"; font.family: root.mono; font.pixelSize: Atelier.iconLg * root.u; color: Qt.alpha(Atelier.text, 0.6) }
        }
        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text { visible: ph.notifs.length > 0; anchors.verticalCenter: parent.verticalCenter; rightPadding: 26 * root.u; text: "󰂚 " + ph.notifs.length; font.family: root.mono; font.pixelSize: Atelier.iconLg * root.u; color: Atelier.yellow }
            Text { visible: ph.hasBattery; anchors.verticalCenter: parent.verticalCenter; rightPadding: 26 * root.u; text: (ph.charging ? "󰂄 " : "󰁹 ") + ph.batPct + "%"; font.family: root.mono; font.pixelSize: Atelier.iconLg * root.u; color: ph.batPct <= 15 && !ph.charging ? Atelier.red : Atelier.text }
            Rectangle {
                width: seg2.width + 36 * root.u; height: statusBar.height; color: Atelier.accent
                Text { id: seg2; anchors.centerIn: parent; text: ph.h1 + ":" + ph.mm + (ph.ampm ? " " + ph.ampm : ""); font.family: root.mono; font.pixelSize: Atelier.iconLg * root.u; font.bold: true; color: Atelier.crust }
            }
        }
    }
}
