.pragma library

// The catalogue of cells one beat can be: every distinct set of onsets on a
// grid of one to four slots, each with its canonical notation. A metronome
// tick has no length, so two spellings with the same onsets are one sound,
// and each mask appears once, spelled the way a player would write it.
//
// An item is a note or a rest: k is the note's value relative to the beat
// note (1 the beat itself, 2 half of it, 4 a quarter of it), dot lengthens
// it by half. Under a tuplet the values are nominal: three of k=2, or five
// or six of k=4, in the time of the beat.

var CELLS = [
    { n: 1, mask: 0b1,    items: [note(1)] },

    { n: 2, mask: 0b11,   items: [note(2), note(2)] },
    { n: 2, mask: 0b10,   items: [rest(2), note(2)] },

    { n: 3, mask: 0b111,  items: [note(2), note(2), note(2)] },
    { n: 3, mask: 0b101,  items: [note(1), note(2)] },
    { n: 3, mask: 0b011,  items: [note(2), note(1)] },
    { n: 3, mask: 0b110,  items: [rest(2), note(2), note(2)] },
    { n: 3, mask: 0b100,  items: [rest(1), note(2)] },
    { n: 3, mask: 0b010,  items: [rest(2), note(2), rest(2)] },

    { n: 4, mask: 0b1111, items: [note(4), note(4), note(4), note(4)] },
    { n: 4, mask: 0b1001, items: [note(2, true), note(4)] },
    { n: 4, mask: 0b0011, items: [note(4), note(2, true)] },
    { n: 4, mask: 0b1101, items: [note(2), note(4), note(4)] },
    { n: 4, mask: 0b0111, items: [note(4), note(4), note(2)] },
    { n: 4, mask: 0b1011, items: [note(4), note(2), note(4)] },
    { n: 4, mask: 0b1110, items: [rest(4), note(4), note(4), note(4)] },
    { n: 4, mask: 0b1010, items: [rest(4), note(4), rest(4), note(4)] },
    { n: 4, mask: 0b1100, items: [rest(2), note(4), note(4)] },
    { n: 4, mask: 0b0110, items: [rest(4), note(4), note(2)] },
    { n: 4, mask: 0b0010, items: [rest(4), note(2, true)] },
    { n: 4, mask: 0b1000, items: [rest(2, true), note(4)] },

    { n: 5, mask: 0b11111,  items: [note(4), note(4), note(4), note(4), note(4)] },
    { n: 5, mask: 0b11110,  items: [rest(4), note(4), note(4), note(4), note(4)] },

    { n: 6, mask: 0b111111, items: [note(4), note(4), note(4), note(4), note(4), note(4)] },
    { n: 6, mask: 0b111110, items: [rest(4), note(4), note(4), note(4), note(4), note(4)] }
]

// The number over a tuplet's group, 0 when the grid is a plain division.
function tuplet(n) { return n === 3 || n === 5 || n === 6 ? n : 0 }

// The nominal value of a grid's notes: halves and quarters for 2 and 4,
// the next power of two below the count for a tuplet.
function nominal(n) { return n === 3 ? 2 : n >= 5 ? 4 : n }

function note(k, dot) { return { rest: false, k: k, dot: dot === true } }
function rest(k, dot) { return { rest: true, k: k, dot: dot === true } }

function cellsFor(n) {
    return CELLS.filter(function (c) { return c.n === n })
}

// The tiles: a grid's cells without a rest. A rest is one tap away in the
// editor's custom row, so the tiles stay the figures a player reaches for.
function tilesFor(n) {
    return cellsFor(n).filter(function (c) {
        return c.items.every(function (it) { return !it.rest })
    })
}

// The cell for a division and a pattern. Spelled literally when asked, or
// when the catalogue has no figure for it: every slot a note or a rest of
// the division's own value. Otherwise the catalogue's figure, which may
// fold a clear slot into a longer note.
function cell(n, mask, rests) {
    if (rests !== true)
        for (var i = 0; i < CELLS.length; i++)
            if (CELLS[i].n === n && CELLS[i].mask === mask) return CELLS[i]
    return literal(n, mask)
}

function literal(n, mask) {
    var items = []
    for (var s = 0; s < n; s++) items.push(mask >> s & 1 ? note(nominal(n)) : rest(nominal(n)))
    return { n: n, mask: mask, items: items }
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
