import QtQuick
import QtQuick.Shapes

// The transport's mark: Phosphor's "play" and "stop" icons, fill weight (MIT,
// see packaging/ICON-LICENSE), the same family the app icon's metronome comes
// from. Drawn as paths rather than typed, because a font's ▶ and ■ are not
// centred on their own ink, differ between fonts, and may be missing
// altogether.
//
// Phosphor balances each icon on its own centre of mass inside the 256 grid:
// the play triangle's centroid sits at (127.6, 128) — its box leans right of
// centre precisely so the shape does not — and the stop square is centred both
// ways. So the grid is centred on the circle and neither mark needs a nudge.
Item {
    id: root

    property bool running: false
    property color ink: "black"
    // The play triangle's height, base to tip, as a fraction of the circle.
    // 0.24 is the weight the marks have always had here; the stop square
    // follows from it at Phosphor's own ratio, so the two read as equals.
    property real mark: width * 0.24

    // Phosphor's ink inside its 256 grid: the triangle is 208.1 tall.
    readonly property real box: root.mark * 256 / 208.1

    readonly property string playPath: "M240,128a15.74,15.74,0,0,1-7.6,13.51L88.32,229.65a16,16,0,0,1-16.2.3A15.86,15.86,0,0,1,64,216.13V39.87a15.86,15.86,0,0,1,8.12-13.82,16,16,0,0,1,16.2.3L232.4,114.49A15.74,15.74,0,0,1,240,128Z"
    readonly property string stopPath: "M216,56V200a16,16,0,0,1-16,16H56a16,16,0,0,1-16-16V56A16,16,0,0,1,56,40H200A16,16,0,0,1,216,56Z"

    Shape {
        width: root.box
        height: root.box
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { xScale: root.box / 256; yScale: root.box / 256 }

        ShapePath {
            fillColor: root.ink
            strokeColor: "transparent"
            PathSvg { path: root.running ? root.stopPath : root.playPath }
        }
    }
}
