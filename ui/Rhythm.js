.pragma library

// The catalogue of cells one beat can be: every distinct set of onsets on a
// grid of one to four slots, each with its canonical notation. A metronome
// tick has no length, so two spellings with the same onsets are one sound,
// and each mask appears once, spelled the way a player would write it.
//
// An item is a note or a rest: k is the note's value relative to the beat
// note (1 the beat itself, 2 half of it, 4 a quarter of it), dot lengthens
// it by half. Under a triplet the values are nominal: three of k=2 in the
// time of the beat.

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
    { n: 4, mask: 0b1000, items: [rest(2, true), note(4)] }
]

function note(k, dot) { return { rest: false, k: k, dot: dot === true } }
function rest(k, dot) { return { rest: true, k: k, dot: dot === true } }

function cellsFor(n) {
    return CELLS.filter(function (c) { return c.n === n })
}

function cell(n, mask) {
    for (var i = 0; i < CELLS.length; i++)
        if (CELLS[i].n === n && CELLS[i].mask === mask) return CELLS[i]
    // A pattern the catalogue does not spell (a hand-written state file):
    // the grid alone, every slot a note.
    var items = []
    for (var s = 0; s < n; s++) items.push(mask >> s & 1 ? note(n === 3 ? 2 : n) : rest(n === 3 ? 2 : n))
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
    var parts = []
    for (var i = 0; i < c.items.length; i++) {
        var it = c.items[i]
        var name = valueName(beatValue, it.k)
        if (it.dot) name = "dotted " + name
        parts.push(it.rest ? name + " rest" : name)
    }
    var text = parts.join(", ")
    if (c.n === 3) text = "triplet " + text
    return text.charAt(0).toUpperCase() + text.slice(1)
}
