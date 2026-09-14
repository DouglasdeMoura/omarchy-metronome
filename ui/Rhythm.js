.pragma library

// The cell one beat is: a division into 1 to 6 slots, a pattern of the
// slots that tick, and a shape of the slots that start a figure. A figure
// runs from its slot to the next figure's; a figure whose own slot ticks is
// a note, one whose slot is silent a rest. So a pattern is a sound and a
// shape is its spelling: a dotted eighth and a sixteenth, or a sixteenth,
// two rests and a sixteenth, tick the same and are drawn apart.
//
// The catalogue: every distinct pattern on a grid of one to four slots,
// and the full quintuplet and sextuplet, each with the shape a player
// would write. A shape equal to its pattern has no rest.

var CELLS = [
    { n: 1, mask: 0b1,      shape: 0b1 },

    { n: 2, mask: 0b11,     shape: 0b11 },
    { n: 2, mask: 0b10,     shape: 0b11 },

    { n: 3, mask: 0b111,    shape: 0b111 },
    { n: 3, mask: 0b101,    shape: 0b101 },
    { n: 3, mask: 0b011,    shape: 0b011 },
    { n: 3, mask: 0b110,    shape: 0b111 },
    { n: 3, mask: 0b100,    shape: 0b101 },
    { n: 3, mask: 0b010,    shape: 0b111 },

    { n: 4, mask: 0b1111,   shape: 0b1111 },
    { n: 4, mask: 0b1001,   shape: 0b1001 },
    { n: 4, mask: 0b0011,   shape: 0b0011 },
    { n: 4, mask: 0b1101,   shape: 0b1101 },
    { n: 4, mask: 0b0111,   shape: 0b0111 },
    { n: 4, mask: 0b1011,   shape: 0b1011 },
    { n: 4, mask: 0b1110,   shape: 0b1111 },
    { n: 4, mask: 0b1010,   shape: 0b1111 },
    { n: 4, mask: 0b1100,   shape: 0b1101 },
    { n: 4, mask: 0b0110,   shape: 0b0111 },
    { n: 4, mask: 0b0010,   shape: 0b0011 },
    { n: 4, mask: 0b1000,   shape: 0b1001 },

    { n: 5, mask: 0b11111,  shape: 0b11111 },
    { n: 5, mask: 0b11110,  shape: 0b11111 },

    { n: 6, mask: 0b111111, shape: 0b111111 },
    { n: 6, mask: 0b111110, shape: 0b111111 }
]

function cellsFor(n) {
    return CELLS.filter(function (c) { return c.n === n })
}

// The tiles: a grid's cells without a rest. A rest is one tap away in the
// editor's ticks, so the tiles stay the figures a player reaches for.
function tilesFor(n) {
    return cellsFor(n).filter(function (c) { return c.shape === c.mask })
}

// The number over a tuplet's group, 0 when the grid is a plain division.
function tuplet(n) { return n === 3 || n === 5 || n === 6 ? n : 0 }

// The nominal value of a grid's slot: halves and quarters for 2 and 4,
// the next power of two below the count for a tuplet.
function nominal(n) { return n === 3 ? 2 : n >= 5 ? 4 : n }

// The slots that start a figure, in order.
function starts(n, shape) {
    var out = []
    for (var s = 0; s < n; s++) if (shape >> s & 1) out.push(s)
    return out
}

// The cell for a division, a pattern and a shape. With no shape given, the
// catalogue's spelling of the pattern, or the literal one: a figure in
// every slot. An item is a note or a rest with k, its value relative to
// the beat note (1 the beat, 2 half of it, 4 a quarter), and a dot.
function cell(n, mask, shape) {
    if (shape === undefined) {
        for (var i = 0; i < CELLS.length; i++)
            if (CELLS[i].n === n && CELLS[i].mask === mask) { shape = CELLS[i].shape; break }
        if (shape === undefined) shape = (1 << n) - 1
    }
    shape = (shape | mask | 1) & ((1 << n) - 1)
    var at = starts(n, shape)
    var items = []
    for (var j = 0; j < at.length; j++) {
        var span = (j + 1 < at.length ? at[j + 1] : n) - at[j]
        var fig = figure(n, span)
        // A span no single figure spells (five sixths of a beat) falls
        // back to a figure per slot.
        if (!fig) return cell(n, mask, (1 << n) - 1)
        items.push({ rest: !(mask >> at[j] & 1), k: fig.k, dot: fig.dot })
    }
    return { n: n, mask: mask, shape: shape, items: items }
}

// The figure for a run of `span` slots on a grid of n: the slot's own
// value for one, twice that for two, dotted for three, four times for
// four, dotted for six, and the beat itself for the whole grid.
function figure(n, span) {
    var u = nominal(n)
    if (span === n) return { k: 1, dot: false }
    if (span === 1) return { k: u, dot: false }
    if (span === 2 && u >= 2) return { k: u / 2, dot: false }
    if (span === 3 && u >= 2) return { k: u / 2, dot: true }
    if (span === 4 && u >= 4) return { k: u / 4, dot: false }
    if (span === 6 && u >= 4) return { k: u / 4, dot: true }
    return null
}

// Names follow the note the signature's bottom makes the beat.
var VALUE_NAMES = {
    1: ["whole", "half", "quarter", "eighth"],
    2: ["half", "quarter", "eighth", "sixteenth"],
    4: ["quarter", "eighth", "sixteenth", "thirty-second"],
    8: ["eighth", "sixteenth", "thirty-second", "sixty-fourth"]
}

function valueName(beatValue, k) {
    var ladder = VALUE_NAMES[beatValue] || VALUE_NAMES[4]
    return ladder[Math.round(Math.log(k) / Math.LN2)]
}

function cellName(beatValue, c) {
    // Runs of one figure fold into a count: "sextuplet sixteenths", "two
    // sixteenths, eighth", never a sixteenth six times over.
    var words = ["", "", "two", "three", "four", "five", "six"]
    var parts = []
    var i = 0
    while (i < c.items.length) {
        var it = c.items[i]
        var run = 1
        while (i + run < c.items.length && same(c.items[i + run], it)) run++
        var name = valueName(beatValue, it.k)
        if (it.dot) name = "dotted " + name
        if (it.rest) name += " rest"
        if (run === 1) parts.push(name)
        else if (run === c.items.length) parts.push(name + "s")
        else parts.push(words[run] + " " + name + "s")
        i += run
    }
    var text = parts.join(", ")
    var tuplets = { 3: "triplet ", 5: "quintuplet ", 6: "sextuplet " }
    if (tuplets[c.n]) text = tuplets[c.n] + text
    return text.charAt(0).toUpperCase() + text.slice(1)
}

function same(a, b) { return a.rest === b.rest && a.k === b.k && a.dot === b.dot }
