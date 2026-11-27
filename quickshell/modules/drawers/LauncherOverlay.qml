import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// Spotlight-style launcher in a Caelestia bottom drawer.
// One search field for: apps (fuzzy + usage-ranked), shell actions (open the
// wallpaper / wifi / bluetooth / clipboard / calendar / session drawers, lock,
// sleep, reboot, screenshot...), an inline calculator, shell commands and web search.
//
// Prefixes: = calculator, ? web, ?? Codex, ??? Claude, ???? Gemini, > actions, $ command
Item {
    id: launchRoot
    visible: false
    anchors.fill: parent    // fills the shared DrawerHost window



    property bool isLight: false
    property bool animActive: false

    signal closedSignal()
    signal requestOverlay(string name)
    signal toastRequested(string msg, string icon, string color)

    // Space Mono Typography & Catppuccin colors
    readonly property string fontMono: Atelier.font
    readonly property color colText: Atelier.text
    readonly property color colSubtext: Atelier.subtext
    readonly property color colMauve: Atelier.accent
    readonly property color colDivider: Atelier.outline
    readonly property color colRowActive: Atelier.pressed
    readonly property color colRowHover: Atelier.hover

    readonly property int rowHeight: 50
    readonly property int rowSpacing: 3
    readonly property int maxRows: 7
    readonly property real cardWidth: Math.min(600, launchRoot.width - 48)
    readonly property real listHeight: Math.max(1, Math.min(results.length, maxRows)) * (rowHeight + rowSpacing) - rowSpacing
    readonly property real answerHeight: Math.min(Math.max(rowHeight, answerText.height), Math.max(rowHeight, Math.min(320, height - 115)))
    readonly property real cardHeight: 14 * 2 + (questionMode ? 42 : 0) + (showAnswer ? answerHeight : listHeight) + 8 + 1 + 8 + 44
    readonly property var questionPrefixes: ({ Codex: "??", Claude: "???", Gemini: "????" })
    readonly property bool questionMode: query.trim().startsWith("??")
    readonly property string questionCli: query.trim().startsWith("????") ? "Gemini" : query.trim().startsWith("???") ? "Claude" : "Codex"
    readonly property string question: questionMode ? query.trim().slice(questionPrefixes[questionCli].length).trim() : ""
    property string submittedQuestion: ""
    property string submittedCli: ""
    property string answer: ""
    property string answerProgress: ""
    property string answerError: ""
    property bool answerReady: false
    property bool cancellingAnswer: false
    readonly property bool showAnswer: question !== "" && question === submittedQuestion && questionCli === submittedCli
    readonly property Item bodyItem: launchCard.contentItem

    readonly property string terminal: Settings.behavior.terminal

    // ── Data sources ─────────────────────────────────────────────────────────
    readonly property var apps: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))

    // Launch counts, persisted in the shell's state dir (used to rank results)
    property var usage: ({})
    FileView {
        id: usageFile
        path: Quickshell.statePath("launcher-usage.json")
        printErrors: false
        onLoaded: {
            try { launchRoot.usage = JSON.parse(text()) || {}; } catch (e) { launchRoot.usage = {}; }
        }
    }
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", Quickshell.stateDir])

    function bump(key) {
        var u = Object.assign({}, usage);
        u[key] = (u[key] || 0) + 1;
        usage = u;
        usageFile.setText(JSON.stringify(u));
    }

    readonly property var actions: baseActions.concat(Plugins.launcherActions)
    readonly property var baseActions: [
        { key: "wallpaper", title: "Wallpapers",      subtitle: "Browse and set wallpapers",            glyph: "󰸉", color: Atelier.accent, words: "wallpaper background picture image wallhaven", overlay: "wallpaper" },
        { key: "wifi",      title: "Wi-Fi",           subtitle: "Networks and connection",              glyph: "󰤨", color: Atelier.sky, words: "wifi wireless network internet connect", overlay: "wifi" },
        { key: "bluetooth", title: "Bluetooth",       subtitle: "Devices, pairing, headphones",         glyph: "󰂯", color: Atelier.blue, words: "bluetooth devices headphones pair earbuds", overlay: "bluetooth" },
        { key: "games",     title: "Games",           subtitle: "Your game library, fullscreen (Super+G)", glyph: "󰊴", color: Atelier.green, words: "games game library steam heroic lutris play gaming console big picture", overlay: "games" },
        { key: "themes",    title: "Themes",          subtitle: "Switch the system-wide colour theme",  glyph: "󰏘", color: Atelier.pink,  words: "theme themes colors colours palette dark light catppuccin gruvbox tokyo nord everforest rose pine dracula", overlay: "theme" },
        { key: "keyboard",  title: "On-screen keyboard", subtitle: "Type with the mouse (Super+/)",        glyph: "󰌌", color: Atelier.sapphire, words: "keyboard virtual on-screen osk type typing keys", overlay: "keyboard" },
        { key: "settings",  title: "Settings",        subtitle: "Customize the shell (Super+,)",         glyph: "󰒓", color: Atelier.accent, words: "settings preferences customize options config bar widgets windows", overlay: "settings" },
        { key: "clipboard", title: "Clipboard",       subtitle: "Clipboard history",                    glyph: "󰅌", color: Atelier.yellow, words: "clipboard history copy paste", overlay: "clipboard" },
        { key: "emoji",     title: "Emoji",           subtitle: "Pick an emoji · Super+;",              glyph: "󰞅", color: Atelier.yellow, words: "emoji emoticon smiley face symbol picker", overlay: "emoji" },
        { key: "gifs",      title: "GIFs",            subtitle: "Find a GIF · Super+Shift+;",           glyph: "󰵸", color: Atelier.pink,   words: "gif gifs giphy tenor meme reaction animated", overlay: "gifs" },
        { key: "sysmon",    title: "System monitor",  subtitle: "CPU, memory, GPU, apps, battery (Super+Shift+M)", glyph: "󰍛", color: Atelier.accent, words: "system monitor task manager cpu ram memory gpu temperature processes htop battery health charge limit", overlay: "sysmon" },
        { key: "scratchpad", title: "Scratchpad",      subtitle: "A quick note, saved as you type (Super+Alt+N)", glyph: "󰎞", color: Atelier.yellow, words: "scratchpad note notes jot memo sticky text", overlay: "scratchpad" },        { key: "timers",    title: "Timers",          subtitle: "Timer, stopwatch, pomodoro (Super+Alt+T)", glyph: "󱎫", color: Atelier.peach, words: "timer stopwatch pomodoro focus countdown alarm clock", overlay: "timers" },
        { key: "software",  title: "Software",        subtitle: "Install and remove apps (Arch repos and AUR)", glyph: "󰏖", color: Atelier.green, words: "software install remove uninstall package packages pacman aur yay paru apps store app store", overlay: "software" },
        { key: "ports",     title: "Ports",           subtitle: "What is listening on localhost (Super+Alt+O)", glyph: "󰛳", color: Atelier.teal, words: "ports listening localhost server dev kill process netstat", overlay: "ports" },
        { key: "colors",    title: "Colour picker",   subtitle: "Pick a colour from the screen",       glyph: "󰈈", color: Atelier.pink, words: "color colour picker eyedropper hex rgb pipette", overlay: "colors" },
        { key: "calendar",  title: "Calendar",        subtitle: "Month view",                           glyph: "󰃭", color: Atelier.green, words: "calendar date month day", overlay: "calendar" },
        { key: "session",   title: "Session",         subtitle: "Lock, sleep, log out, restart, power", glyph: "󰐥", color: Atelier.red, words: "session power menu logout shutdown", overlay: "power" },
        { key: "lock",      title: "Lock Screen",     subtitle: "hyprlock",                             glyph: "󰌾", color: Atelier.blue, words: "lock screen", cmd: "qs ipc call lock lock || hyprlock" },
        { key: "sleep",     title: "Sleep",           subtitle: "Suspend to RAM",                       glyph: "󰤄", color: Atelier.lavender, words: "sleep suspend", cmd: "systemctl suspend" },
        { key: "logout",    title: "Log Out",         subtitle: "Exit Hyprland",                        glyph: "󰍃", color: Atelier.yellow, words: "log out logout exit quit hyprland", cmd: "hyprctl dispatch 'hl.dsp.exit()' 2>/dev/null || hyprctl dispatch exit" },
        { key: "reboot",    title: "Restart",         subtitle: "Reboot the computer",                  glyph: "󰑓", color: Atelier.green, words: "restart reboot", cmd: "systemctl reboot" },
        { key: "poweroff",  title: "Shut Down",       subtitle: "Power off the computer",               glyph: "⏻",  color: Atelier.red, words: "shut down shutdown power off poweroff turn off", cmd: "systemctl poweroff" },
        { key: "shot",      title: "Screenshot",        subtitle: "Select a region (Print / Super+P)",    glyph: "󰩭", color: Atelier.teal, words: "screenshot screen capture region snip area", overlay: "screenshot" },
        { key: "shotwin",   title: "Screenshot Window", subtitle: "Pick a window (Super+Ctrl+P)",         glyph: "󰖯", color: Atelier.teal, words: "screenshot window capture snip", overlay: "screenshot-window" },
        { key: "shotfull",  title: "Screenshot Screen", subtitle: "Whole screen (Shift+Print)",           glyph: "󰍹", color: Atelier.teal, words: "screenshot full screen capture print", overlay: "screenshot-screen" }
    ]

    // ── Matching ─────────────────────────────────────────────────────────────
    // 0 = no match; higher is better. Subsequence matching only for short fields.
    function match(text, q, subseq) {
        if (!text) return 0;
        var t = String(text).toLowerCase();
        if (t === q) return 100;
        if (t.startsWith(q)) return 85 - Math.min(10, (t.length - q.length) * 0.3);
        var w = t.search(new RegExp("[\\s\\-_.]" + q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
        if (w >= 0) return 70;
        var i = t.indexOf(q);
        if (i >= 0) return 55 - Math.min(i, 15);
        if (!subseq) return 0;
        var from = 0, last = -1, gaps = 0;
        for (var k = 0; k < q.length; k++) {
            var f = t.indexOf(q[k], from);
            if (f < 0) return 0;
            if (last >= 0) gaps += f - last - 1;
            last = f; from = f + 1;
        }
        return Math.max(1, 35 - gaps * 2);
    }

    function usageBoost(key) {
        return Math.min(20, (usage[key] || 0) * 2);
    }

    // ── Calculator ───────────────────────────────────────────────────────────
    readonly property var mathNames: /\b(sqrt|cbrt|sin|cos|tan|asin|acos|atan|log10|log2|log|ln|abs|floor|ceil|round|exp|pow|min|max|pi|e)\b/g

    function calculate(q) {
        var e = q.trim();
        if (e.startsWith("=")) e = e.slice(1).trim();
        if (!e) return null;
        e = e.replace(/×/g, "*").replace(/÷/g, "/").replace(/\^/g, "**");
        if (!/[+\-*/%(]/.test(e)) return null;                       // needs an operation
        if (!/^[0-9+\-*/%().,\s]*$/.test(e.replace(mathNames, ""))) return null;
        if (!/[0-9]|\bpi\b|\be\b/.test(e)) return null;
        var js = e.replace(mathNames, function (m) {
            return { ln: "Math.log", log: "Math.log10", pi: "Math.PI", e: "Math.E" }[m] || ("Math." + m);
        });
        try {
            var v = Function('"use strict"; return (' + js + ');')();
            if (typeof v === "number" && isFinite(v)) return Number(v.toPrecision(12));
        } catch (err) {}
        return null;
    }

    // ── Results ──────────────────────────────────────────────────────────────
    readonly property string query: searchInput.text
    readonly property var results: {
        var raw = query.trim();
        if (raw.startsWith("??")) return question ? [questionItem(question, questionCli)] : [];

        var prefix = raw.length > 0 && "=?>$".indexOf(raw[0]) >= 0 ? raw[0] : "";
        var q = (prefix ? raw.slice(1) : raw).trim().toLowerCase();
        var out = [];

        if (prefix === "?") {
            if (q) out.push(webItem(q));
            return out;
        }
        if (prefix === "$") {
            if (q) {
                var cmd = raw.slice(1).trim();
                out.push({ kind: "run", title: "Run  " + cmd, subtitle: "Run in the background", glyph: "󰐊", color: Atelier.green, tag: "Command",
                           run: function () { launchRoot.exec(["sh", "-c", cmd]); } });
                out.push({ kind: "run", title: "Run in terminal  " + cmd, subtitle: launchRoot.terminal, glyph: "󰆍", color: Atelier.teal, tag: "Command",
                           run: function () { launchRoot.exec([launchRoot.terminal, "-e", "sh", "-c", cmd + "; echo; read -n1 -p 'press any key'"]); } });
            }
            return out;
        }

        var calc = calculate(prefix === "=" ? "=" + q : raw);
        if (calc !== null) {
            var shown = String(calc);
            out.push({ kind: "calc", title: "= " + shown, subtitle: (prefix === "=" ? q : raw) + "   ·   Enter to copy", glyph: "󰃬", color: Atelier.yellow, tag: "Calculator",
                       run: function () {
                           Quickshell.execDetached(["wl-copy", shown]);
                           launchRoot.toastRequested("Copied " + shown, "󰃬", Atelier.yellow);
                           launchRoot.close();
                       } });
        }
        if (prefix === "=") return out;

        var scored = [];
        // Actions
        for (var a = 0; a < actions.length; a++) {
            var act = actions[a];
            // empty query: suggest the shell drawers; ">" lists every action
            var s = q ? Math.max(match(act.title, q, true), match(act.words, q, false) * 0.8)
                      : (prefix === ">" ? 50 : (act.overlay ? 30 : 0));
            if (s > 0) scored.push({ score: s + usageBoost("act:" + act.key) + 5, item: actionItem(act) });
        }
        // Apps
        if (prefix !== ">") {
            for (var i = 0; i < apps.length; i++) {
                var app = apps[i];
                var as = 0;
                if (!q) {
                    as = 1;
                } else {
                    as = Math.max(match(app.name, q, true),
                                  match(app.genericName, q, false) * 0.7,
                                  match((app.keywords || []).join(" "), q, false) * 0.6,
                                  match(app.comment, q, false) * 0.4);
                }
                if (as > 0) scored.push({ score: as + usageBoost("app:" + app.id), item: appItem(app) });
            }
        }
        // explicit tie-break: the JS engine's sort is not stable
        scored.sort(function (x, y) { return (y.score - x.score) || x.item.title.localeCompare(y.item.title); });
        for (var j = 0; j < scored.length && j < 60; j++) out.push(scored[j].item);

        if (q && prefix !== ">") out.push(webItem(raw));
        return out;
    }

    function appItem(app) {
        var icon = app.icon || "";
        var src = icon.startsWith("/") ? "file://" + icon : (icon ? Quickshell.iconPath(icon, true) : "");
        return {
            // apps whose icon is missing from the theme get a letter tile instead of the checkerboard
            kind: src ? "app" : "appGlyph", title: app.name,
            subtitle: app.comment || app.genericName || (app.command || []).join(" "),
            icon: src, glyph: app.name.charAt(0).toUpperCase(), color: Atelier.lavender,
            tag: "App",
            run: function () {
                launchRoot.bump("app:" + app.id);
                if (app.runInTerminal) launchRoot.exec([launchRoot.terminal, "-e"].concat(app.command));
                else { app.execute(); launchRoot.close(); }
            }
        };
    }

    function actionItem(act) {
        return {
            kind: "action", title: act.title, subtitle: act.subtitle, glyph: act.glyph, color: act.color,
            tag: act.overlay ? "Open" : "Action",
            run: function () {
                launchRoot.bump("act:" + act.key);
                if (act.overlay) {
                    launchRoot.requestOverlay(act.overlay);   // shell closes us and opens the drawer
                } else {
                    launchRoot.exec(["sh", "-c", act.cmd]);
                    if (act.toast) launchRoot.toastRequested(act.toast, act.glyph, act.color);
                }
            }
        };
    }

    function webItem(q) {
        return {
            kind: "web", title: "Search the web for “" + q + "”", subtitle: "Opens in your browser", glyph: "󰖟", color: Atelier.blue, tag: "Web",
            run: function () { launchRoot.exec(["xdg-open", Settings.behavior.searchUrl + encodeURIComponent(q)]); }
        };
    }

    function questionItem(question, cli) {
        return {
            kind: "web", title: "Ask " + cli + ": “" + question + "”", subtitle: "Answer here using " + cli + " CLI",
            glyph: "󰭹", color: Atelier.teal, tag: cli,
            run: function () { launchRoot.submitQuestion(question, cli); }
        };
    }

    function submitQuestion(question, cli) {
        const sameQuestion = question === submittedQuestion && cli === submittedCli;
        if (chatProcess.running) {
            if (!sameQuestion)
                toastRequested(submittedCli + " is still answering your previous question", "󰭹", Atelier.teal);
            return;
        }
        if (sameQuestion && answerReady) return;
        submittedQuestion = question;
        submittedCli = cli;
        answer = "";
        answerError = "";
        answerProgress = "Asking " + cli + "…";
        answerReady = false;
        cancellingAnswer = false;
        answerView.contentY = 0;
        const prompt = "Give the direct answer first, in plain text. Default to one short paragraph unless the question asks for more. Do not use tools.\n\n" + question;
        const commands = {
            Gemini: ["python3", Quickshell.shellDir + "/scripts/gemini-question.py", prompt],
            Claude: ["claude", "-p", "--model", "haiku", "--tools", "", "--strict-mcp-config", "--no-session-persistence", "--", prompt],
            Codex: ["codex", "--ask-for-approval", "never", "exec", "--ignore-user-config", "--skip-git-repo-check",
                    "--ephemeral", "--sandbox", "read-only", "--color", "never", "--", prompt]
        };
        chatProcess.command = ["sh", "-c", 'PATH="$PATH:$HOME/.local/bin"; export PATH; exec "$@" </dev/null',
                               "atelier-launcher", "timeout", "--kill-after=5s", "90s"].concat(commands[cli]);
        chatProcess.running = true;
    }

    Process {
        id: chatProcess
        workingDirectory: "/tmp"
        stdout: StdioCollector {
            id: chatOutput
            waitForEnd: false
            onDataChanged: {
                const reply = text.trim();
                if (reply && !launchRoot.cancellingAnswer) launchRoot.answer = reply;
            }
        }
        stderr: SplitParser {
            onRead: line => {
                const marker = "ATELIER_GEMINI: ";
                if (launchRoot.submittedCli === "Gemini" && line.startsWith(marker))
                    launchRoot.answerError = line.slice(marker.length);
                if (/^Reconnecting\.\.\. \d+\/\d+/i.test(line.trim()))
                    launchRoot.answerProgress = "Reconnecting to " + launchRoot.submittedCli + "…";
            }
        }
        onExited: (code, status) => {
            if (launchRoot.cancellingAnswer)
                launchRoot.answer = "Cancelled. Press Enter to retry.";
            else if (code === 0 && status === 0 && launchRoot.answer !== "")
                launchRoot.answerReady = true;
            else if (code === 124 || code === 137)
                launchRoot.answer = launchRoot.submittedCli + " did not return an answer within 90 seconds. Press Enter to retry.";
            else if (code === 127)
                launchRoot.answer = launchRoot.submittedCli + " CLI was not found.";
            else if (code === 0 && status === 0)
                launchRoot.answer = launchRoot.submittedCli + " returned an empty answer. Press Enter to retry.";
            else if (launchRoot.answerError)
                launchRoot.answer = launchRoot.answerError;
            else
                launchRoot.answer = launchRoot.submittedCli + " could not answer. Check your CLI login and connection, then press Enter to retry.";
        }
    }

    function exec(argv) {
        launchRoot.close();
        Quickshell.execDetached(argv);
    }

    function activate(index) {
        if (showAnswer) {
            submitQuestion(question, questionCli);
            return;
        }
        if (index >= 0 && index < results.length) results[index].run();
    }

    onResultsChanged: {
        resultsList.currentIndex = 0;
        resultsList.positionViewAtBeginning();
    }

    // ── Open / close ─────────────────────────────────────────────────────────
    function toggle() {
        if (visible && animActive) close();
        else open();
    }

    function open() {
        visible = true;
        animActive = true;
        searchInput.text = "";
        usageFile.reload();
        resultsList.currentIndex = 0;
        resultsList.positionViewAtBeginning();
        focusTimer.restart();
    }

    // Open with text already typed (e.g. "=" for calculator mode, "?" for web)
    function openWith(text) {
        if (!visible || !animActive) open();
        searchInput.text = text;
        searchInput.cursorPosition = text.length;
    }

    function close() {
        animActive = false;
        closeTimer.restart();
        closedSignal();
    }

    Timer {
        id: focusTimer
        interval: 30
        repeat: false
        onTriggered: searchInput.forceActiveFocus()
    }

    Timer {
        id: closeTimer
        interval: Atelier.durClose + 40
        repeat: false
        onTriggered: {
            if (!launchRoot.animActive) launchRoot.visible = false;
        }
    }

    // Click outside to dismiss
    MouseArea {
        anchors.fill: parent
        onClicked: launchRoot.close()
    }

    // ── Drawer rising from the bottom edge (Caelestia-style) ────────────────
    EdgeDrawer {
        id: launchCard
        edge: "bottom"
        open: launchRoot.animActive
        bodyWidth: launchRoot.cardWidth
        bodyHeight: launchRoot.cardHeight

        Behavior on bodyHeight {
            NumberAnimation { duration: Atelier.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Atelier.curveStandard }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            RowLayout {
                visible: launchRoot.questionMode
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                spacing: 6

                Repeater {
                    model: ["Codex", "Claude", "Gemini"]
                    Chip {
                        required property string modelData
                        text: modelData
                        variant: "secondary"
                        selected: modelData === launchRoot.questionCli
                        interactive: true
                        onClicked: {
                            launchRoot.openWith(launchRoot.questionPrefixes[modelData] + " " + launchRoot.question);
                            searchInput.forceActiveFocus();
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Chip {
                    visible: launchRoot.showAnswer && launchRoot.answerReady
                    text: "Copy"
                    interactive: true
                    onClicked: {
                        Quickshell.execDetached(["wl-copy", "--", launchRoot.answer]);
                        launchRoot.toastRequested("Answer copied", "󰆏", Atelier.teal);
                    }
                }

                Chip {
                    visible: launchRoot.showAnswer && !chatProcess.running
                    text: "New"
                    interactive: true
                    onClicked: {
                        launchRoot.openWith(launchRoot.questionPrefixes[launchRoot.questionCli] + " ");
                        searchInput.forceActiveFocus();
                    }
                }
            }

            // ── Results (best match sits right above the search field) ──────
            ListView {
                id: resultsList
                visible: !launchRoot.showAnswer
                verticalLayoutDirection: ListView.BottomToTop
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: launchRoot.rowSpacing
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                model: launchRoot.results

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool isCurrent: resultsList.currentIndex === index

                    width: resultsList.width
                    height: launchRoot.rowHeight

                    Rectangle {
                        anchors.fill: parent
                        radius: Atelier.radiusMd
                        color: row.isCurrent ? launchRoot.colRowActive : (rowMa.containsMouse ? launchRoot.colRowHover : "transparent")
                        Behavior on color { CAnim {} }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 12
                        spacing: 12

                        // Icon: app icon, or a tinted glyph tile for actions/calc/web
                        Item {
                            implicitWidth: 34
                            implicitHeight: 34
                            Layout.alignment: Qt.AlignVCenter

                            IconImage {
                                anchors.fill: parent
                                visible: row.modelData.kind === "app"
                                source: row.modelData.icon || ""
                                asynchronous: true
                            }

                            Rectangle {
                                anchors.fill: parent
                                visible: row.modelData.kind !== "app"
                                radius: 11
                                color: row.modelData.color ? Qt.alpha(row.modelData.color, 0.16) : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: row.modelData.glyph || ""
                                    font.family: launchRoot.fontMono
                                    font.pixelSize: 17
                                    color: row.modelData.color || launchRoot.colText
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                font.family: Atelier.fontUi
                                font.pixelSize: row.modelData.kind === "calc" ? 15 : 13
                                font.bold: true
                                color: launchRoot.colText
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: row.modelData.subtitle || ""
                                font.family: Atelier.fontUi
                                font.pixelSize: Atelier.fsMicro
                                color: launchRoot.colSubtext
                                opacity: 0.8
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: row.isCurrent ? row.modelData.tag + "  ↵" : row.modelData.tag
                            font.family: Atelier.fontUi
                            font.pixelSize: Atelier.fsMicro
                            color: row.isCurrent ? launchRoot.colMauve : launchRoot.colSubtext
                            Behavior on color { CAnim {} }
                            opacity: row.isCurrent ? 1 : 0.6
                        }
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: launchRoot.activate(row.index)
                        onPositionChanged: resultsList.currentIndex = row.index
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    active: resultsList.moving || resultsList.flicking
                    policy: ScrollBar.AsNeeded
                }

                Text {
                    anchors.centerIn: parent
                    visible: launchRoot.results.length === 0
                    text: launchRoot.questionMode ? "Type a question for " + launchRoot.questionCli
                        : launchRoot.query.trim().length > 1 ? "No results" : "Type a command, sum, or app"
                    font.family: Atelier.fontUi
                    font.pixelSize: Atelier.fsMd
                    color: launchRoot.colSubtext
                    opacity: 0.7
                }
            }

            Flickable {
                id: answerView
                visible: launchRoot.showAnswer
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: answerText.height
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                TextEdit {
                    id: answerText
                    width: Math.max(1, answerView.width - 20)
                    height: contentHeight + topPadding + bottomPadding
                    padding: 8
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    text: launchRoot.answer || (chatProcess.running ? launchRoot.answerProgress : "")
                    font.family: Atelier.fontUi
                    font.pixelSize: Atelier.fsMd
                    color: launchRoot.colText
                    Keys.onEscapePressed: launchRoot.close()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: launchRoot.colDivider
            }

            // ── Search field (bottom, next to the edge) ────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                spacing: 12

                Text {
                    text: {
                        var c = launchRoot.query.trim()[0];
                        return c === "=" ? "󰃬" : c === "?" ? "󰖟" : c === ">" ? "󱓞" : c === "$" ? "󰆍" : "󰍉";
                    }
                    font.family: Atelier.fontUi
                    font.pixelSize: 18
                    color: launchRoot.colMauve
                    Layout.alignment: Qt.AlignVCenter
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    font.family: Atelier.fontUi
                    font.pixelSize: 14
                    font.bold: true
                    color: launchRoot.colText
                    selectByMouse: true
                    clip: true
                    focus: true

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !searchInput.text
                        text: "Search apps, actions, or calculate…"
                        font.family: Atelier.fontUi
                        font.pixelSize: Atelier.fsLg
                        color: launchRoot.colSubtext
                        opacity: 0.6
                    }

                    Keys.onEscapePressed: launchRoot.close()
                    // List grows upward, so Up moves away from the search field
                    Keys.onUpPressed: resultsList.incrementCurrentIndex()
                    Keys.onDownPressed: resultsList.decrementCurrentIndex()
                    Keys.onTabPressed: resultsList.incrementCurrentIndex()
                    Keys.onBacktabPressed: resultsList.decrementCurrentIndex()
                    Keys.onReturnPressed: launchRoot.activate(resultsList.currentIndex)
                    Keys.onEnterPressed: launchRoot.activate(resultsList.currentIndex)
                }

                // Prefix hints while empty, clear button while typing
                Text {
                    visible: !searchInput.text
                    Layout.alignment: Qt.AlignVCenter
                    text: "= calc   ? web   ?? ask AI   > actions   $ run"
                    font.family: Atelier.fontUi
                    font.pixelSize: Atelier.fsMicro
                    color: launchRoot.colSubtext
                    opacity: 0.55
                }

                Chip {
                    visible: chatProcess.running
                    interactive: !launchRoot.cancellingAnswer
                    tint: Atelier.red
                    text: launchRoot.cancellingAnswer ? "Cancelling…" : "Cancel"
                    onClicked: {
                        launchRoot.cancellingAnswer = true;
                        chatProcess.signal(15); // SIGTERM, forwarded to Codex by timeout
                        searchInput.forceActiveFocus();
                    }
                }

                Rectangle {
                    visible: searchInput.text.length > 0
                    implicitWidth: 24
                    implicitHeight: 24
                    radius: Atelier.radiusMd
                    color: clearMa.containsMouse ? launchRoot.colRowActive : "transparent"
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        font.family: launchRoot.fontMono
                        font.pixelSize: Atelier.fsMd
                        color: launchRoot.colSubtext
                    }

                    MouseArea {
                        id: clearMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { searchInput.text = ""; searchInput.forceActiveFocus(); }
                    }
                }
            }
        }
    }
}
