import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config

// Settings → Keyboard & mouse. Everything is Settings.input, written to atelier-settings.lua and
// applied live by Settings.qml (atelier-mode.lua M.apply_input).
ColumnLayout {
    id: page
    Layout.fillWidth: true
    spacing: 20

    readonly property var i: Settings.input

    // which kinds of pointer are plugged in (shows only the cards that apply)
    property bool hasTouchpad: true
    property bool hasMouse: true
    property bool hasCurveMouse: false
    Process {
        id: devProc
        running: page.visible
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const mice = JSON.parse(text).mice || [];
                    page.hasTouchpad = mice.some(m => /touchpad/i.test(m.name));
                    page.hasMouse = mice.some(m => !/touchpad|consumer-control/i.test(m.name));
                    page.hasCurveMouse = mice.some(m => m.name === "mosart-semi.-2.4g-keyboard-mouse-1");
                } catch (e) {}
            }
        }
    }

    // a place to try the keyboard settings (repeat, layout) without leaving the page
    SettingCard {
        title: "Keyboard"
        SettingField { label: "Layouts"; description: "Keyboard layout codes, comma separated: us, de, fr, in…"; placeholder: "us"; fieldWidth: 160
            text: page.i.kbLayout; onCommitted: (t) => Settings.input.kbLayout = t.replace(/\s+/g, "") || "us" }
        SettingField { visible: page.i.kbLayout.indexOf(",") >= 0 || page.i.kbVariant !== ""
            label: "Variants"; description: "One per layout, comma separated; empty uses the standard one"; placeholder: ",nodeadkeys"; fieldWidth: 160
            text: page.i.kbVariant; onCommitted: (t) => Settings.input.kbVariant = t.replace(/\s+/g, "") }
        SettingChoice { visible: page.i.kbLayout.indexOf(",") >= 0
            label: "Switch layouts with"
            options: [{ id: "grp:alt_shift_toggle", label: "Alt+Shift" }, { id: "grp:win_space_toggle", label: "Super+Space" },
                      { id: "grp:ctrl_shift_toggle", label: "Ctrl+Shift" }, { id: "grp:caps_toggle", label: "Caps Lock" }, { id: "", label: "None" }]
            value: page.i.layoutSwitch; onPicked: (id) => Settings.input.layoutSwitch = id }
        SettingChoice {
            label: "Caps Lock key"
            options: [{ id: "default", label: "Caps Lock" }, { id: "escape", label: "Escape" }, { id: "ctrl", label: "Ctrl" },
                      { id: "swapescape", label: "Swap with Esc" }, { id: "off", label: "Off" }]
            value: page.i.capsLock; onPicked: (id) => Settings.input.capsLock = id }
        SettingSlider { label: "Repeat delay"; description: "How long to hold a key before it repeats"; from: 150; to: 1000; step: 25; suffix: " ms"
            value: page.i.repeatDelay; onMoved: (v) => Settings.input.repeatDelay = Math.round(v) }
        SettingSlider { label: "Repeat rate"; description: "Characters per second while held"; from: 10; to: 80; step: 1; suffix: " /s"
            value: page.i.repeatRate; onMoved: (v) => Settings.input.repeatRate = Math.round(v) }
        SettingSwitch { label: "Num Lock on at login"
            checked: page.i.numlock; onToggled: (v) => Settings.input.numlock = v }
        SettingRow {
            label: "Try it"
            description: "Hold a key here to feel the repeat settings"
            Rectangle {
                implicitWidth: 220; implicitHeight: 34; radius: 17
                color: Atelier.containerHigh
                border.width: 1
                border.color: tryIn.activeFocus ? Qt.alpha(Atelier.accent, 0.6) : Atelier.outline
                TextInput {
                    id: tryIn
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                    verticalAlignment: Text.AlignVCenter
                    font.family: Atelier.fontUi; font.pixelSize: 12; color: Atelier.text
                    clip: true; selectByMouse: true
                }
            }
        }
        SettingField { label: "Other keyboard options"; description: "Extra xkb options, comma separated (e.g. compose:ralt)"; placeholder: "none"; fieldWidth: 200
            text: page.i.kbOptions; onCommitted: (t) => Settings.input.kbOptions = t.replace(/\s+/g, "") }
    }

    SettingCard {
        visible: page.hasMouse
        title: "Mouse"
        SettingSlider { label: "Pointer speed"; description: "0 is the device's own speed"; from: -1; to: 1; step: 0.05; decimals: 2
            value: page.i.sensitivity; onMoved: (v) => Settings.input.sensitivity = Math.round(v * 100) / 100 }
        SettingChoice { label: "Acceleration"; description: "Flat moves the pointer exactly as far as the mouse"
            options: [{ id: "adaptive", label: "Adaptive" }, { id: "flat", label: "Flat" }]
            value: page.i.accelProfile; onPicked: (id) => Settings.input.accelProfile = id }
        SettingSwitch { visible: page.hasCurveMouse
            label: "Smooth acceleration curve"; description: "macOS-style curve on the 2.4 GHz mouse: precise when slow, quick on flicks"
            checked: page.i.mouseCurve; onToggled: (v) => Settings.input.mouseCurve = v }
        SettingSwitch { label: "Natural scrolling"; description: "Content moves with the wheel, like a touchscreen"
            checked: page.i.naturalScroll; onToggled: (v) => Settings.input.naturalScroll = v }
        SettingSlider { label: "Scroll speed"; from: 0.2; to: 3; step: 0.05; decimals: 2; suffix: "×"
            value: page.i.scrollFactor; onMoved: (v) => Settings.input.scrollFactor = Math.round(v * 100) / 100 }
        SettingSwitch { label: "Left-handed"; description: "Swap the left and right buttons"
            checked: page.i.leftHanded; onToggled: (v) => Settings.input.leftHanded = v }
    }

    SettingCard {
        visible: page.hasTouchpad
        title: "Touchpad"
        SettingSwitch { label: "Natural scrolling"; description: "Content follows your fingers"
            checked: page.i.tpNatural; onToggled: (v) => Settings.input.tpNatural = v }
        SettingSlider { label: "Scroll speed"; from: 0.1; to: 2; step: 0.05; decimals: 2; suffix: "×"
            value: page.i.tpScroll; onMoved: (v) => Settings.input.tpScroll = Math.round(v * 100) / 100 }
        SettingSwitch { label: "Tap to click"
            checked: page.i.tpTap; onToggled: (v) => Settings.input.tpTap = v }
        SettingSwitch { label: "Click with fingers"; description: "Two-finger click is a right click, three-finger a middle click"
            checked: page.i.tpClickfinger; onToggled: (v) => Settings.input.tpClickfinger = v }
        SettingSwitch { label: "Ignore while typing"
            checked: page.i.tpDwt; onToggled: (v) => Settings.input.tpDwt = v }
        SettingSwitch { visible: page.i.tpTap; label: "Drag lock"; description: "Lifting a finger in the middle of a tap-drag doesn't drop it"
            checked: page.i.tpDragLock; onToggled: (v) => Settings.input.tpDragLock = v }
    }

    // hypr/conf/input.lua. Turning a gesture on/off or changing fingers reloads Hyprland (it can't
    // remove a gesture); direction, distance and new workspaces apply live.
    SettingCard {
        id: gestureCard
        visible: page.hasTouchpad
        title: "Touchpad gestures"
        readonly property int swipeFingers: page.i.gestureFingers === 4 ? 4 : 3
        readonly property int otherFingers: 7 - swipeFingers
        SettingSwitch { label: "Swipe between workspaces"; description: "Slide sideways; the workspace follows your fingers"
            checked: page.i.gestureWorkspace; onToggled: (v) => Settings.input.gestureWorkspace = v }
        SettingChoice { visible: page.i.gestureWorkspace || page.i.gestureOverview
            label: "Workspace swipe fingers"; description: "The overview swipe uses the other count"
            options: [{ id: "3", label: "Three" }, { id: "4", label: "Four" }]
            value: String(gestureCard.swipeFingers); onPicked: (id) => Settings.input.gestureFingers = Number(id) }
        SettingSwitch { visible: page.i.gestureWorkspace; label: "Reverse direction"; description: "Swipe left to go to the next workspace"
            checked: page.i.gestureInvert; onToggled: (v) => Settings.input.gestureInvert = v }
        SettingSwitch { visible: page.i.gestureWorkspace; label: "Make a new workspace at the end"; description: "Swiping past the last one opens an empty workspace"
            checked: page.i.gestureCreateNew; onToggled: (v) => Settings.input.gestureCreateNew = v }
        SettingSlider { visible: page.i.gestureWorkspace; label: "Swipe distance"; description: "How far to slide for one workspace; shorter is quicker"
            from: 100; to: 800; step: 25; suffix: " px"
            value: page.i.gestureDistance; onMoved: (v) => Settings.input.gestureDistance = Math.round(v) }
        SettingSwitch { label: "Swipe up for the overview"
            description: gestureCard.otherFingers + " fingers up opens every workspace at a glance, down closes it"
            checked: page.i.gestureOverview; onToggled: (v) => Settings.input.gestureOverview = v }
        SettingSwitch { label: "Pinch for the launcher"; description: "Pinch in to open the launcher, spread out to close it"
            checked: page.i.gestureLauncher; onToggled: (v) => Settings.input.gestureLauncher = v }
        SettingChoice { visible: page.i.gestureLauncher
            label: "Pinch fingers"; description: "Two-finger pinch stays with apps (zoom in browsers, image viewers)"
            options: [{ id: "3", label: "Three" }, { id: "4", label: "Four" }]
            value: String(page.i.pinchFingers === 3 ? 3 : 4); onPicked: (id) => Settings.input.pinchFingers = Number(id) }
    }

    SettingCard {
        title: "Pointer"
        SettingSwitch { label: "Focus follows the pointer"; description: "Windows get the keyboard when the pointer moves onto them"
            checked: page.i.followMouse; onToggled: (v) => Settings.input.followMouse = v }
    }
}
