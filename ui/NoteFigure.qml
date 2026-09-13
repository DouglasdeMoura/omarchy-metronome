import QtQuick

// A rhythm figure, drawn, not typed: the notes one beat splits into, with
// their stems, beams or flags, and the 3 of a triplet. Typed note glyphs
// beyond a quaver fall back to tofu on most fonts; ink here follows the
// theme like everything else.
Canvas {
    id: root

    // The note the beat is: 1 whole, 2 half, 4 quarter, 8 eighth.
    property int beatValue: 4
    // Notes per beat, 1 to 4. Three is a triplet: three of the next shorter
    // value in the time of the beat.
    property int division: 1
    property color ink: Theme.color.foreground

    readonly property int noteValue: division === 3 ? beatValue * 2 : beatValue * division
    // Quaver one beam, semiquaver two, demisemiquaver three.
    readonly property int beams: noteValue >= 8 ? Math.round(Math.log(noteValue / 4) / Math.LN2) : 0
    readonly property bool hollow: noteValue <= 2
    readonly property bool stemmed: noteValue >= 2

    readonly property real unit: Theme.font.body
    readonly property real headRx: unit * 0.32
    readonly property real headRy: unit * 0.23
    readonly property real stemH: unit * 1.15
    readonly property real step: unit * 0.95
    readonly property real beamGap: unit * 0.28
    readonly property real tripletRoom: division === 3 ? unit * 0.7 : 0

    implicitWidth: Math.ceil(headRx * 2 + (division - 1) * step + unit * 0.5)
    implicitHeight: Math.ceil(headRy * 2 + stemH + tripletRoom + unit * 0.2)

    onBeatValueChanged: requestPaint()
    onDivisionChanged: requestPaint()
    onInkChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.strokeStyle = root.ink
        ctx.fillStyle = root.ink
        ctx.lineCap = "round"
        var baseY = height - headRy - unit * 0.1
        var x0 = headRx + unit * 0.1
        var stemTop = baseY - stemH
        var thin = Math.max(1, unit / 12)

        // The heads, and a stem on each that has one.
        for (var i = 0; i < division; i++) {
            var cx = x0 + i * step
            ctx.save()
            ctx.translate(cx, baseY)
            ctx.rotate(-0.35)
            ctx.beginPath()
            ctx.ellipse(-headRx, -headRy, headRx * 2, headRy * 2)
            ctx.restore()
            if (root.hollow) {
                ctx.lineWidth = thin * 1.4
                ctx.stroke()
            } else {
                ctx.fill()
            }
            if (root.stemmed) {
                var sx = cx + headRx * 0.85
                ctx.lineWidth = thin
                ctx.beginPath()
                ctx.moveTo(sx, baseY - headRy * 0.4)
                ctx.lineTo(sx, stemTop)
                ctx.stroke()
            }
        }

        // Beams join a group; a note alone carries flags instead.
        if (root.beams > 0) {
            var left = x0 + headRx * 0.85
            var right = x0 + (division - 1) * step + headRx * 0.85
            for (var b = 0; b < root.beams; b++) {
                var y = stemTop + b * beamGap + thin
                if (division > 1) {
                    ctx.lineWidth = thin * 2.2
                    ctx.lineCap = "butt"
                    ctx.beginPath()
                    ctx.moveTo(left - thin / 2, y)
                    ctx.lineTo(right + thin / 2, y)
                    ctx.stroke()
                    ctx.lineCap = "round"
                } else {
                    ctx.lineWidth = thin * 1.6
                    ctx.beginPath()
                    ctx.moveTo(left, y)
                    ctx.quadraticCurveTo(left + unit * 0.35, y + unit * 0.15, left + unit * 0.3, y + unit * 0.55)
                    ctx.stroke()
                }
            }
        }

        // The triplet's 3, over the group, with a bracket when nothing beams it.
        if (division === 3) {
            var mid = x0 + step + headRx * 0.4
            var ty = stemTop - unit * 0.25
            ctx.font = "bold " + Math.round(unit * 0.6) + "px " + Theme.font.family
            ctx.textAlign = "center"
            ctx.textBaseline = "alphabetic"
            ctx.fillText("3", mid, ty)
            if (root.beams === 0) {
                ctx.lineWidth = thin
                ctx.beginPath()
                ctx.moveTo(x0 - headRx * 0.2, ty + unit * 0.1)
                ctx.lineTo(x0 - headRx * 0.2, ty - unit * 0.2)
                ctx.lineTo(mid - unit * 0.35, ty - unit * 0.2)
                ctx.moveTo(mid + unit * 0.35, ty - unit * 0.2)
                ctx.lineTo(x0 + 2 * step + headRx, ty - unit * 0.2)
                ctx.lineTo(x0 + 2 * step + headRx, ty + unit * 0.1)
                ctx.stroke()
            }
        }
    }
}
