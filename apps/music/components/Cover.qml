import QtQuick
import QtQuick.Shapes
import qs.config

// Album art with smooth rounded corners, kept cheap so a page of covers stays light:
//  - decoded at the size it is shown (× the screen scale), no mipmaps;
//  - rounded by an anti-aliased Shape that uses the image as its fill (ShapePath.fillItem),
//    so there is no offscreen buffer per cover (the shell's MultiEffect mask cost ~0.5 MB each);
//  - wide video thumbnails are centred and cropped to the square instead of stretched.
// A tile + glyph shows until the image has loaded.
Item {
    id: ri
    property alias source: img.source
    property real radius: Atelier.radiusMd
    property string placeholder: "󰎆"
    property color tile: Atelier.containerHigh
    property int decode: 0                       // unused (kept for callers); size comes from the item
    readonly property bool ready: img.status === Image.Ready
    readonly property real dpr: Screen.devicePixelRatio || 1

    Rectangle {
        anchors.fill: parent
        radius: ri.radius
        color: ri.tile
        visible: !ri.ready
        Text {
            anchors.centerIn: parent
            text: ri.placeholder
            font.family: Atelier.font
            font.pixelSize: Math.round(ri.height * 0.36)
            color: Atelier.subtext
        }
    }

    // The source texture, laid out as a centred "crop" box (hidden: the Shape draws it).
    Image {
        id: img
        readonly property real aspect: implicitHeight > 0 ? implicitWidth / implicitHeight : 1
        width: aspect >= 1 ? ri.height * aspect : ri.width
        height: aspect >= 1 ? ri.height : ri.width / aspect
        x: (ri.width - width) / 2
        y: (ri.height - height) / 2
        visible: false
        fillMode: Image.Stretch
        asynchronous: true
        smooth: true
        mipmap: false
        // decode only as many pixels as are shown (shortest side = the cover's side)
        sourceSize.height: Math.ceil(Math.max(ri.width, ri.height) * ri.dpr)
    }

    Shape {
        anchors.fill: parent
        visible: ri.ready
        preferredRendererType: Shape.CurveRenderer
        opacity: ri.ready ? 1 : 0
        Behavior on opacity { Anim { type: "slowEffects" } }
        ShapePath {
            strokeWidth: -1
            fillItem: img
            // the fill is drawn at the texture's own pixel size: scale it to the crop box, or a
            // small source (a 544 px cover shown at 600 px) would smear its last row/column
            fillTransform: PlanarTransform.fromTranslate(img.x, img.y)
                .times(PlanarTransform.fromScale(img.width / Math.max(1, img.implicitWidth),
                                                 img.height / Math.max(1, img.implicitHeight)))
            PathRectangle { width: ri.width; height: ri.height; radius: ri.radius }
        }
    }
}
