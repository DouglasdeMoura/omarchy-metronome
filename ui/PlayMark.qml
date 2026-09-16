import QtQuick

// The transport's mark, drawn rather than typed. A font's ▶ and ■ are not
// centred on their own ink, differ between fonts, and may be missing
// altogether; drawn, the triangle sits on its centroid and the square on its
// middle, so both are exactly centred in the circle at any size.
Canvas {
    id: root

    property bool running: false
    property color ink: "black"
    // The mark's height: the triangle's base-to-tip and, a touch smaller so
    // the two read as equals, the square's side. 0.24 of the circle is the
    // weight the typed marks had.
    property real mark: Math.round(width * 0.24)

    onRunningChanged: requestPaint()
    onInkChanged: requestPaint()
    onMarkChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.fillStyle = root.ink
        var cx = width / 2
        var cy = height / 2

        if (root.running) {
            var side = root.mark * 0.88
            ctx.fillRect(Math.round(cx - side / 2), Math.round(cy - side / 2), Math.round(side), Math.round(side))
            return
        }

        // An equilateral triangle pointing right, placed so its centroid,
        // a third of the way back from the tip, lands on the centre.
        var h = root.mark                 // the height, base to tip
        var w = h * 0.866                 // the width of an equilateral triangle
        var left = cx - w / 3             // the base, a third of the width back
        ctx.beginPath()
        ctx.moveTo(left, cy - h / 2)
        ctx.lineTo(left + w, cy)
        ctx.lineTo(left, cy + h / 2)
        ctx.closePath()
        ctx.fill()
    }
}
