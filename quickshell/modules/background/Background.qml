import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.services

// Wallpaper layer drawn by the shell itself: instant apply, no external daemon.
// Two slots (A/B) swap roles; the incoming one is revealed by the transition picked in
// Settings → Appearance → Wallpaper (Settings.appearance.wallTransition):
//   none · fade (crossfade + settle zoom) · wipe · slide · grow (circle from the centre) · zoom
//   · spread (cells eat through from a few random colonies with a glowing edge: shaders/spread.frag)
//   · outline (the new wallpaper's subject is drawn as a line, filled in, then the rest spreads
//     out of it: shaders/outline.frag, maps from scripts/wallfx.py. A wallpaper that isn't
//     prepared yet plays spread while its maps are made in the background for next time.)
// Hyprland's blur is paused while a transition runs (see blur()): it made every style stall.
// One `progress` value (0 → 1) drives every style. Nothing animates (and no mask layer
// exists) outside a transition, so the idle cost is zero.
PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    color: "black"

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "atelier-wallpaper"

    readonly property Item slotA: slots.count > 0 ? slots.itemAt(0) : null
    readonly property Item slotB: slots.count > 1 ? slots.itemAt(1) : null
    property Item front: null
    readonly property Item back: front === slotA ? slotB : slotA
    readonly property string target: Wallpaper.current

    readonly property var styles: ["fade", "wipe", "slide", "grow", "zoom", "spread", "outline"]
    property string style: "fade"          // resolved for the running transition ("random" picks one)
    property string dir: "left"            // wipe / slide: the edge the new wallpaper comes from
    property real progress: 1
    readonly property bool running: anim.running

    onTargetChanged: load()

    function load() {
        if (!slotA || !slotB) return;
        if (!front) front = slotA;
        if (!target) return;
        const url = "file://" + target;
        if (front.source == url) return;
        if (front.status !== Image.Ready) {   // first load: no transition
            front.source = url;
            front.shown = true;
            return;
        }
        anim.stop();
        if (anim.pending) finish();           // a transition was cut short: settle it first
        const s = Settings.appearance.wallTransition || "fade";
        style = s === "random" ? styles[Math.floor(Math.random() * styles.length)] : s;
        dir = Settings.appearance.wallDirection || "left";
        progress = 0;
        back.shown = false;
        if (style !== "none") blur(false);     // before the image decodes, so it lands in time
        if (style === "outline") {             // is this wallpaper prepared? (fast lookup)
            mapPending = true;
            mapImg.source = ""; penImg.source = "";
            mapProc.running = false;
            mapProc.command = ["python3", root.wallfx, "map", target];
            mapProc.running = true;
        }
        back.source = url;                     // the transition starts when it finishes decoding
    }

    // Hyprland re-blurs the whole screen on every frame while the wallpaper changes (its blur
    // caches the still wallpaper): blur pauses for the transition (scripts/wallblur.sh).
    readonly property string wallblur: Quickshell.shellDir + "/scripts/wallblur.sh"
    function blur(on) {
        Quickshell.execDetached([wallblur, on ? "on" : "off"]);
        if (on) blurSafety.stop(); else blurSafety.restart();
    }
    Timer { id: blurSafety; interval: 8000; onTriggered: if (!anim.pending) root.blur(true) }   // a load that never finished

    // starts once the new image (and, for outline, its maps) are ready
    function tryBegin() {
        if (!back || back.shown || progress !== 0 || back.status !== Image.Ready || mapPending) return;
        if (style === "outline" && (mapImg.status !== Image.Ready || penImg.status !== Image.Ready)) return;
        begin();
    }

    // ── outline: the per-wallpaper maps ──
    readonly property string wallfx: Quickshell.shellDir + "/scripts/wallfx.py"
    property bool mapPending: false
    Process {
        id: mapProc
        stdout: StdioCollector {
            onStreamFinished: {
                const r = text.trim().split(" ");
                if (r.length === 2) {
                    mapImg.source = "file://" + r[0];
                    penImg.source = "file://" + r[1];
                } else {
                    root.style = "spread";      // no subject, or not prepared yet
                    if (r[0] === "missing")     // prepare it quietly for next time
                        Quickshell.execDetached(["nice", "-n", "15", "python3", root.wallfx, "make", root.target]);
                }
                root.mapPending = false;
                root.tryBegin();
            }
        }
    }
    // texture providers for the shader (never drawn themselves)
    Image { id: mapImg; width: 1; height: 1; opacity: 0; asynchronous: true; cache: false; smooth: true
        onStatusChanged: { if (status === Image.Ready) root.tryBegin(); else if (status === Image.Error && root.style === "outline") { root.style = "spread"; root.tryBegin(); } } }
    Image { id: penImg; width: 1; height: 1; opacity: 0; asynchronous: true; cache: false; smooth: true
        onStatusChanged: { if (status === Image.Ready) root.tryBegin(); else if (status === Image.Error && root.style === "outline") { root.style = "spread"; root.tryBegin(); } } }

    function begin() {
        Wallpaper.transitioning = true;        // the theme waits until we are done
        if (style === "spread") newColonies();
        back.z = 1;
        front.z = 0;
        back.shown = true;
        anim.pending = true;
        if (style === "none" || Settings.appearance.wallDuration <= 0) { progress = 1; finish(); return; }
        anim.start();
    }

    function finish() {
        anim.pending = false;
        blur(true);
        Wallpaper.transitioning = false;
        progress = 1;
        const old = front;
        front = back;
        old.shown = false;
        old.source = "";
    }

    readonly property real dx: dir === "left" ? -1 : dir === "right" ? 1 : 0   // where it comes FROM
    readonly property real dy: dir === "top" ? -1 : dir === "bottom" ? 1 : 0

    // the two slots (a Repeater rather than an inline component: Quickshell rejects that here)
    Repeater {
    id: slots
    model: 2
    onItemAdded: if (count === 2) Qt.callLater(root.load)
    delegate: Item {
        id: slot
        required property int index
        property alias source: img.source
        property alias status: img.status
        property alias image: img
        property bool shown: false
        readonly property bool incoming: slot === root.back && shown && root.progress < 1
        readonly property bool outgoing: slot === root.front && root.back.shown && root.progress < 1
        readonly property real p: root.progress

        width: root.width
        height: root.height
        visible: shown || outgoing

        // whole-slot motion: slide moves the slot, the outgoing one drifts the other way (parallax)
        x: incoming && root.style === "slide" ? root.dx * root.width * (1 - p)
         : outgoing && root.style === "slide" ? -root.dx * root.width * 0.3 * p : 0
        y: incoming && root.style === "slide" ? root.dy * root.height * (1 - p)
         : outgoing && root.style === "slide" ? -root.dy * root.height * 0.3 * p : 0
        opacity: incoming && (root.style === "fade" || root.style === "zoom") ? p
               : outgoing && root.style === "slide" ? 1 - 0.35 * p : 1

        // wipe: a clip box that grows from the chosen edge; the image inside stays put
        Item {
            id: clipper
            readonly property bool wiping: slot.incoming && root.style === "wipe"
            clip: wiping
            width: wiping && root.dx !== 0 ? root.width * slot.p : root.width
            height: wiping && root.dy !== 0 ? root.height * slot.p : root.height
            x: wiping && root.dx > 0 ? root.width - width : 0
            y: wiping && root.dy > 0 ? root.height - height : 0

            Image {
                id: img
                x: -clipper.x
                y: -clipper.y
                width: root.width
                height: root.height
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                // decode at screen resolution, not the file's (4K PNGs are ~30 MB as textures)
                sourceSize.width: root.width * (root.screen ? root.screen.devicePixelRatio : 1)
                sourceSize.height: root.height * (root.screen ? root.screen.devicePixelRatio : 1)
                transformOrigin: Item.Center
                scale: slot.incoming && root.style === "fade" ? 1.04 - 0.04 * slot.p
                     : slot.incoming && root.style === "zoom" ? 1.18 - 0.18 * slot.p
                     : slot.incoming && root.style === "grow" ? 1.08 - 0.08 * slot.p
                     : slot.outgoing && root.style === "zoom" ? 1 - 0.06 * slot.p
                     : 1
                onStatusChanged: {
                    if (status === Image.Ready && slot === root.back) root.tryBegin();
                    else if (status === Image.Error && slot === root.back) root.blur(true);
                }
            }
        }

        // grow: a soft-edged circle mask from the centre, only while it runs
        readonly property bool masking: incoming && root.style === "grow"
        layer.enabled: masking
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: circle
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.25
        }
        Item {
            id: circle
            width: root.width
            height: root.height
            visible: false
            layer.enabled: slot.masking
            Rectangle {
                readonly property real d: Math.hypot(root.width, root.height) * 1.1 * slot.p
                width: d
                height: d
                radius: d / 2
                anchors.centerIn: parent
                color: "white"
            }
        }
    }

    }

    // ── spread: one full-screen shader over both slots, only while it runs ──
    function crop(im) {    // the part of the decoded image that PreserveAspectCrop shows
        if (!im) return Qt.vector4d(0, 0, 1, 1);
        const iw = im.implicitWidth, ih = im.implicitHeight;
        if (!iw || !ih || !root.height) return Qt.vector4d(0, 0, 1, 1);
        const sa = root.width / root.height, ia = iw / ih;
        return ia > sa ? Qt.vector4d((1 - sa / ia) / 2, 0, sa / ia, 1)
                       : Qt.vector4d(0, (1 - ia / sa) / 2, 1, ia / sa);
    }
    // The arrival map: when each 4 px cell flips. Rendered ONCE per change into a small
    // half-float texture (480×270 on 1080p), so a frame of the transition only reads it.
    readonly property int cellPx: 4
    ShaderEffect {
        id: spreadMap
        width: Math.max(1, Math.ceil(root.width / root.cellPx))
        height: Math.max(1, Math.ceil(root.height / root.cellPx))
        // drawn only into mapSource (hideSource)
        property real aspect: root.width / Math.max(1, root.height)
        property real seed: 0
        property vector4d c0; property vector4d c1; property vector4d c2; property vector4d c3; property vector4d c4
        fragmentShader: Qt.resolvedUrl("../../shaders/spreadmap.frag.qsb")
    }
    ShaderEffectSource {
        id: mapSource
        sourceItem: spreadMap
        hideSource: true
        // redrawn every frame while a spread runs (480×270: cheap), frozen otherwise. A one-shot
        // capture (live: false + scheduleUpdate) was never drawn before the effect sampled it,
        // which froze the old wallpaper and then cut to the new one.
        live: anim.pending && root.style === "spread"
        format: ShaderEffectSource.RGBA16F
        smooth: true
        width: 1; height: 1; opacity: 0
    }
    function newColonies() {
        const asp = root.width / Math.max(1, root.height);
        const c = [];
        for (let i = 0; i < 5; i++)    // the first lands at once, the others a little later
            c.push(Qt.vector4d((0.08 + Math.random() * 0.84) * asp, 0.08 + Math.random() * 0.84, i === 0 ? 0 : Math.random() * 0.38, 0));
        spreadMap.seed = Math.random() * 100;
        spreadMap.c0 = c[0]; spreadMap.c1 = c[1]; spreadMap.c2 = c[2]; spreadMap.c3 = c[3]; spreadMap.c4 = c[4];
        // the latest arrival (same formula as spreadmap.frag, without the noise): sample a grid
        let mx = 0;
        for (let gy = 0; gy <= 18; gy++) for (let gx = 0; gx <= 32; gx++) {
            const px = gx / 32 * asp, py = gy / 18;
            let a = 10;
            for (const k of c) a = Math.min(a, k.z + Math.hypot(px - k.x, py - k.y) * 0.62);
            mx = Math.max(mx, a);
        }
        spread.amax = mx + 0.08;     // + the noise's reach
    }

    ShaderEffect {
        id: spread
        anchors.fill: parent
        z: 10
        visible: root.style === "spread" && anim.pending && !!root.front && !!root.back
        property real t: root.progress
        property real gw: spreadMap.width
        property real gh: spreadMap.height
        property real seed: spreadMap.seed
        property real glow: 1
        property real amax: 1
        property vector4d cropOld: root.crop(oldTex)
        property vector4d cropNew: root.crop(newTex)
        property color ember: Atelier.accent
        property variant oldTex: root.front ? root.front.image : null
        property variant newTex: root.back ? root.back.image : null
        property variant mapTex: mapSource
        fragmentShader: Qt.resolvedUrl("../../shaders/spread.v3.frag.qsb")
    }

    ShaderEffect {
        id: outlineFx
        anchors.fill: parent
        z: 10
        visible: root.style === "outline" && anim.pending && !!root.front && !!root.back
        property real t: root.progress
        property real sw: width
        property real sh: height
        property real mw: mapImg.implicitWidth
        property real mh: mapImg.implicitHeight
        property real sdRange: 12          // wallfx.py SD
        property real lineW: 2
        property real cell: 4
        property vector4d cropOld: root.crop(oldTex)
        property vector4d cropNew: root.crop(newTex)
        property color ink: Atelier.text
        property variant oldTex: root.front ? root.front.image : null
        property variant newTex: root.back ? root.back.image : null
        property variant mapTex: mapImg
        property variant penTex: penImg
        fragmentShader: Qt.resolvedUrl("../../shaders/outline.v1.frag.qsb")
    }

    NumberAnimation {
        id: anim
        property bool pending: false
        target: root
        property: "progress"
        from: 0
        to: 1
        // spread needs time to read as a spreading front: never under 1.2 s
        duration: root.style === "outline" ? Math.max(2400, Settings.appearance.wallDuration * 3)
                : root.style === "spread" ? Math.max(1200, Settings.appearance.wallDuration * 1.6)
                : Math.max(1, Settings.appearance.wallDuration)
        easing.type: root.style === "spread" || root.style === "outline" ? Easing.Linear   // the shader eases itself
                   : root.style === "slide" || root.style === "wipe" ? Easing.InOutCubic : Easing.OutCubic
        onFinished: root.finish()
    }
}
