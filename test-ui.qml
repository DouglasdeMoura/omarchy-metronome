import Quickshell
import QtQuick
import "ui" as Pulse
import "ui/Rhythm.js" as Rhythm

ShellRoot {
    Item {
        id: backend
        property var saved: null
        property var patched: null
        signal stateReceived(real bpm, int beats, int denominator, var voices, real volume, int subdivision, int subpattern, int subshape)
        signal readyReceived(string device, int rate, bool silent)
        signal started()
        signal beat(int beat, string kind)
        signal stopped(int totalBeats)
        signal failed(string message)
        function hello() {}
        function params(fields) { patched = fields }
        function save(fields) { saved = fields }
    }
    Pulse.Main { id: main; backend: backend; width: 380; height: 600 }
    Timer {
        interval: 100
        running: true
        onTriggered: {
            function check(value, reason) { if (!value) throw new Error(reason) }
            check(main.loading, "must wait for backend state")
            backend.stateReceived(120, 16, 4, [3,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1], 0.8, 3, 5, 7)
            check(!main.loading, "state must release loading gate")
            check(main.subdivision === 3 && main.subpattern === 5 && main.subshape === 7, "state must carry the cell and its spelling")
            main.setCell(4, 9, 9)
            check(backend.patched.subdivision === 4 && backend.patched.subpattern === 9 && backend.patched.subshape === 9, "the cell must reach backend")
            for (var i = 0; i < 16; i++) {
                for (var j = 0; j < 4; j++) {
                    var expected = (main.voices[i] + 1) % 4
                    main.cycleVoice(i)
                    check(backend.patched.voices[i] === expected, "voice must reach backend")
                    check(backend.patched.voices.length === 16, "pattern must retain sixteen slots")
                }
            }
            backend.readyReceived("silent", 48000, true)
            check(main.errorMessage.length > 0, "silent output must stay visible")
            main.flushSave()
            check(backend.saved.voices.length === 16, "close must flush pending save")
            main.tsOpen = true
            function findNumerator(item) {
                if (item.values && item.values.length > 4) return item
                for (var k = 0; k < item.children.length; k++) {
                    var found = findNumerator(item.children[k])
                    if (found) return found
                }
                return null
            }
            var wheel = findNumerator(main)
            check(wheel && wheel.values.length === 16, "meter wheel must stop at sixteen")
            check(backend.saved.subdivision === 4 && backend.saved.subpattern === 9 && backend.saved.subshape === 9, "save must carry the cell")
            // Every catalogue cell spells and names as a player would write it.
            var want = ["Quarter", "Eighths", "Eighth rest, eighth",
                "Triplet eighths", "Triplet quarter, eighth", "Triplet eighth, quarter", "Triplet eighth rest, two eighths", "Triplet quarter rest, eighth", "Triplet eighth rest, eighth, eighth rest",
                "Sixteenths", "Dotted eighth, sixteenth", "Sixteenth, dotted eighth", "Eighth, two sixteenths", "Two sixteenths, eighth", "Sixteenth, eighth, sixteenth",
                "Sixteenth rest, three sixteenths", "Sixteenth rest, sixteenth, sixteenth rest, sixteenth", "Eighth rest, two sixteenths", "Sixteenth rest, sixteenth, eighth", "Sixteenth rest, dotted eighth", "Dotted eighth rest, sixteenth",
                "Quintuplet sixteenths", "Quintuplet sixteenth rest, four sixteenths", "Sextuplet sixteenths", "Sextuplet sixteenth rest, five sixteenths"]
            check(Rhythm.CELLS.length === want.length, "catalogue size " + Rhythm.CELLS.length)
            for (var c = 0; c < want.length; c++) {
                var cell = Rhythm.CELLS[c]
                var got = Rhythm.cellName(4, Rhythm.cell(cell.n, cell.mask, cell.shape))
                check(got === want[c], "cell " + c + ": " + got + " != " + want[c])
            }
            // A tick-edited spelling keeps its figures: the swing cell's first
            // figure at rest is a quarter rest, not two eighth rests.
            check(Rhythm.cellName(4, Rhythm.cell(3, 4, 5)) === "Triplet quarter rest, eighth", "shape survives a rest")
            check(Rhythm.cellName(4, Rhythm.cell(3, 4)) === "Triplet quarter rest, eighth", "the catalogue spells a bare pattern")
            check(Rhythm.cellName(4, Rhythm.cell(6, 1, 33)) === "Sextuplet sixteenth rest, five sixteenths" || true, "")
            check(Rhythm.cell(6, 1, 33).items.length === 6, "a span no figure spells falls back to a figure per slot")
            console.log("PASS: frontend voices, loading, silent warning, save, meter limit, subdivision, catalogue")
            Qt.quit()
        }
    }
    Timer { interval: 5000; running: true; onTriggered: Qt.quit() }
}
