import QtQuick
import "Rhythm.js" as Rhythm

// A rhythm figure, drawn, not typed: the cell one beat is, with heads,
// stems, beams or flags, dots, rests, and a triplet's 3. Typed note glyphs
// beyond a quaver fall back to tofu on most fonts; ink here follows the
// theme like everything else.
Canvas {
    id: root

    // The note the beat is: 1 whole, 2 half, 4 quarter, 8 eighth.
    property int beatValue: 4
    // The cell: its grid and its pattern, see Rhythm.js.
    property int division: 1
    property int mask: 1
    // The spelling: the slots that start a figure, see Rhythm.js. Unset,
    // the catalogue's spelling of the pattern.
    property var shape: undefined
    property color ink: Theme.color.foreground

    readonly property var cell: Rhythm.cell(division, mask, shape)

    // The drawn ink's bounds, measured after each paint, and how far its
    // centre sits from the box's centre.
    property real inkX: 0
    property real inkY: 0
    property real inkWidth: 0
    property real inkHeight: 0
    readonly property real inkOffsetX: inkWidth > 0 ? Math.round(inkX + inkWidth / 2 - width / 2) : 0
    readonly property real inkOffsetY: inkHeight > 0 ? Math.round(inkY + inkHeight / 2 - height / 2) : 0
    readonly property int tuplet: Rhythm.tuplet(division)

    // The figure's scale: the body size by default, smaller for a chip.
    property real unit: Theme.font.body
    readonly property real headRx: unit * 0.32
    readonly property real headRy: unit * 0.23
    readonly property real stemH: unit * 1.15
    // Five or six notes close ranks, so a sextuplet still fits its button.
    readonly property real step: unit * (cell.items.length > 4 ? 0.68 : 0.95)
    readonly property real beamGap: unit * 0.28
    readonly property real tripletRoom: tuplet ? unit * 0.7 : 0

    implicitWidth: Math.ceil(headRx * 2 + (cell.items.length - 1) * step + unit * 0.5 + dots() * unit * 0.2)
    implicitHeight: Math.ceil(headRy * 2 + stemH + tripletRoom + unit * 0.2)

    function dots() {
        var d = 0
        for (var i = 0; i < cell.items.length; i++) if (cell.items[i].dot) d++
        return d
    }

    // The written value of an item: the beat note times k, so a quarter
    // beat's k=2 is an eighth. Whole 1, half 2, quarter 4, eighth 8...
    function value(item) { return root.beatValue * item.k }
    // Quaver one beam, semiquaver two, demisemiquaver three.
    function beamsOf(item) {
        var v = value(item)
        return v >= 8 ? Math.round(Math.log(v / 4) / Math.LN2) : 0
    }

    onBeatValueChanged: requestPaint()
    onDivisionChanged: requestPaint()
    onMaskChanged: requestPaint()
    onShapeChanged: requestPaint()
    onInkChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.strokeStyle = root.ink
        ctx.fillStyle = root.ink
        ctx.lineCap = "round"
        var items = root.cell.items
        var baseY = height - headRy - unit * 0.1
        var stemTop = baseY - stemH
        var thin = Math.max(1, unit / 12)

        // Positions: one step per item, a little more after a dot.
        var xs = []
        var x = headRx + unit * 0.1
        for (var i = 0; i < items.length; i++) {
            xs.push(x)
            x += step + (items[i].dot ? unit * 0.2 : 0)
        }
        var notes = []
        for (var j = 0; j < items.length; j++) if (!items[j].rest) notes.push(j)

        for (var i2 = 0; i2 < items.length; i2++) {
            var it = items[i2]
            var cx = xs[i2]
            if (it.rest) {
                drawRest(ctx, cx, baseY, value(it), thin)
            } else {
                var v = value(it)
                ctx.save()
                ctx.translate(cx, baseY)
                ctx.rotate(-0.35)
                ctx.beginPath()
                ctx.ellipse(-headRx, -headRy, headRx * 2, headRy * 2)
                ctx.restore()
                if (v <= 2) {
                    ctx.lineWidth = thin * 1.4
                    ctx.stroke()
                } else {
                    ctx.fill()
                }
                if (v >= 2) {
                    ctx.lineWidth = thin
                    ctx.beginPath()
                    ctx.moveTo(stemX(cx), baseY - headRy * 0.4)
                    ctx.lineTo(stemX(cx), stemTop)
                    ctx.stroke()
                }
            }
            if (it.dot) {
                ctx.beginPath()
                ctx.arc(cx + headRx + unit * 0.22, baseY - unit * 0.12, thin * 1.1, 0, 2 * Math.PI)
                ctx.fill()
            }
        }

        // Beams join the notes of the cell, across a rest between them; a
        // level a note has and its neighbours lack is a stub toward the
        // note it belongs with; a note beamed to nothing carries flags.
        var maxBeams = 0
        for (var m = 0; m < notes.length; m++) maxBeams = Math.max(maxBeams, beamsOf(items[notes[m]]))
        for (var level = 1; level <= maxBeams; level++) {
            var y = stemTop + (level - 1) * beamGap + thin
            for (var a = 0; a < notes.length; a++) {
                var ia = notes[a]
                if (beamsOf(items[ia]) < level) continue
                var prev = a > 0 && beamsOf(items[notes[a - 1]]) >= level
                var next = a + 1 < notes.length && beamsOf(items[notes[a + 1]]) >= level
                if (next) {
                    beam(ctx, stemX(xs[ia]), stemX(xs[notes[a + 1]]), y, thin)
                } else if (!prev) {
                    if (notes.length === 1) {
                        flag(ctx, stemX(xs[ia]), y, thin)
                    } else {
                        // A stub: left when a note stands before it, else right.
                        var dir = a > 0 ? -1 : 1
                        beam(ctx, stemX(xs[ia]), stemX(xs[ia]) + dir * unit * 0.45, y, thin)
                    }
                }
            }
        }

        // The tuplet's number over the cell, with a bracket when the cell
        // is not one beamed group: a rest or an unbeamed note in it.
        if (root.tuplet) {
            var left = xs[0] - headRx * 0.2
            var right = xs[items.length - 1] + headRx
            var mid = (left + right) / 2
            var ty = stemTop - unit * 0.25
            // The number never shrinks past legibility, whatever the scale.
            ctx.font = "bold " + Math.round(Math.max(unit * 0.6, Theme.font.caption * 0.75)) + "px " + Theme.font.family
            ctx.textAlign = "center"
            ctx.textBaseline = "alphabetic"
            ctx.fillText(String(root.tuplet), mid, ty)
            var beamed = notes.length === items.length && notes.length > 1 && maxBeams > 0
            for (var q = 0; q < notes.length && beamed; q++) if (beamsOf(items[notes[q]]) === 0) beamed = false
            if (!beamed) {
                ctx.lineWidth = thin
                ctx.beginPath()
                ctx.moveTo(left, ty + unit * 0.1)
                ctx.lineTo(left, ty - unit * 0.2)
                ctx.lineTo(mid - unit * 0.35, ty - unit * 0.2)
                ctx.moveTo(mid + unit * 0.35, ty - unit * 0.2)
                ctx.lineTo(right, ty - unit * 0.2)
                ctx.lineTo(right, ty + unit * 0.1)
                ctx.stroke()
            }
        }

        // Where the ink landed. The box is not the drawing: it keeps room
        // for flags on the right and for a tuplet's number on top, so a
        // figure centred by its box sits off true. A holder centres the ink
        // with inkOffsetX and inkOffsetY instead.
        var w = Math.floor(width)
        var h = Math.floor(height)
        if (w > 0 && h > 0) {
            var d = ctx.getImageData(0, 0, w, h).data
            var minX = w, minY = h, maxX = -1, maxY = -1
            for (var py = 0; py < h; py++) {
                for (var px = 0; px < w; px++) {
                    if (d[(py * w + px) * 4 + 3] > 24) {
                        if (px < minX) minX = px
                        if (px > maxX) maxX = px
                        if (py < minY) minY = py
                        if (py > maxY) maxY = py
                    }
                }
            }
            if (maxX >= 0) {
                root.inkX = minX
                root.inkY = minY
                root.inkWidth = maxX - minX + 1
                root.inkHeight = maxY - minY + 1
            }
        }
    }

    function stemX(cx) { return cx + headRx * 0.85 }

    function beam(ctx, x1, x2, y, thin) {
        ctx.lineWidth = thin * 2.2
        ctx.lineCap = "butt"
        ctx.beginPath()
        ctx.moveTo(x1 - thin / 2, y)
        ctx.lineTo(x2 + thin / 2, y)
        ctx.stroke()
        ctx.lineCap = "round"
    }

    function flag(ctx, x, y, thin) {
        ctx.lineWidth = thin * 1.6
        ctx.beginPath()
        ctx.moveTo(x, y)
        ctx.quadraticCurveTo(x + unit * 0.35, y + unit * 0.15, x + unit * 0.3, y + unit * 0.55)
        ctx.stroke()
    }

    // Rests: a crotchet's zigzag, a quaver's hooked stroke, one hook more
    // for each halving after that.
    function drawRest(ctx, cx, baseY, v, thin) {
        var top = baseY - unit * 1.0
        if (v <= 4) {
            ctx.lineWidth = thin * 2
            ctx.beginPath()
            ctx.moveTo(cx - unit * 0.12, top + unit * 0.05)
            ctx.lineTo(cx + unit * 0.18, top + unit * 0.35)
            ctx.lineTo(cx - unit * 0.1, top + unit * 0.6)
            ctx.lineTo(cx + unit * 0.14, top + unit * 0.9)
            ctx.stroke()
            return
        }
        var hooks = Math.round(Math.log(v / 4) / Math.LN2)
        ctx.lineWidth = thin * 1.3
        ctx.beginPath()
        ctx.moveTo(cx + unit * 0.28, top + unit * 0.15)
        ctx.lineTo(cx - unit * 0.05, top + unit * 1.0)
        ctx.stroke()
        for (var h = 0; h < hooks; h++) {
            var hy = top + unit * 0.15 + h * unit * 0.3
            var hx = cx + unit * 0.28 - h * unit * 0.1
            ctx.beginPath()
            ctx.arc(hx - unit * 0.22, hy, thin * 1.4, 0, 2 * Math.PI)
            ctx.fill()
            ctx.lineWidth = thin
            ctx.beginPath()
            ctx.moveTo(hx - unit * 0.22, hy)
            ctx.quadraticCurveTo(hx - unit * 0.05, hy + unit * 0.14, hx, hy)
            ctx.stroke()
        }
    }
}
