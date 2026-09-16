import Quickshell
import QtQuick
import "ui" as Winkel
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
    Winkel.Main { id: main; backend: backend; width: 380; height: 600 }
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
                var got = Rhythm.cellName(4, Rhythm.cell(cell.n, cell.mask, cell.shape), Winkel.I18n)
                check(got === want[c], "cell " + c + ": " + got + " != " + want[c])
            }
            // A tick-edited spelling keeps its figures: the swing cell's first
            // figure at rest is a quarter rest, not two eighth rests.
            check(Rhythm.cellName(4, Rhythm.cell(3, 4, 5), Winkel.I18n) === "Triplet quarter rest, eighth", "shape survives a rest")
            check(Rhythm.cellName(4, Rhythm.cell(3, 4), Winkel.I18n) === "Triplet quarter rest, eighth", "the catalogue spells a bare pattern")
            check(Rhythm.cell(6, 1, 33).items.length === 6, "a span no figure spells falls back to a figure per slot")
            // Localization: English is the source, a locale switch retranslates
            // bound text in place, plural rules follow the language, and a
            // right-to-left language mirrors the layout.
            var I18n = Winkel.I18n
            check(I18n.locale === "en" && I18n.tr("dialog.ok") === "OK", "the tests run in English")
            check(I18n.tr("app.name") === "Winkel", "the app's name is a catalogue word")
            check(main.tempoName === "Moderato", "the tempo marking comes from the catalogue")
            check(I18n.tr("note.sixteenth", { count: 2 }) === "two sixteenths", "an exact plural form")
            check(I18n.tr("note.sixteenth", { count: 9 }) === "9 sixteenths", "the other form fills its count")
            check(I18n.tr("error.backendExited", { code: 3 }) === "The backend exited with code 3", "placeholders fill")
            check(I18n.normalize("pt_BR.UTF-8@euro") === "pt_BR" && I18n.normalize("pt-br") === "pt_BR" && I18n.normalize("C") === "en", "locale names normalize")
            I18n.setLocale("ru")
            check(I18n.pluralCategory(1) === "one" && I18n.pluralCategory(3) === "few" && I18n.pluralCategory(5) === "many" && I18n.pluralCategory(21) === "one", "russian plurals")
            check(I18n.tr("dialog.ok") === "OK", "a locale without a catalogue falls back to English")
            I18n.setLocale("ar_EG")
            check(I18n.pluralCategory(0) === "zero" && I18n.pluralCategory(2) === "two" && I18n.pluralCategory(11) === "many" && I18n.pluralCategory(100) === "other", "arabic plurals")
            check(I18n.rtl && main.LayoutMirroring.enabled, "a right-to-left language mirrors the layout")
            I18n.setLocale("pseudo")
            check(!I18n.rtl && !main.LayoutMirroring.enabled, "pseudo stays left to right")
            check(main.errorMessage.indexOf("⟦") === 0, "bound text retranslates: " + main.errorMessage)
            check(main.tempoName.indexOf("⟦") === 0, "the tempo marking retranslates")
            var pseudoName = Rhythm.cellName(4, Rhythm.cell(4, 15, 15), I18n)
            check(pseudoName.indexOf("sixteenth") < 0 && pseudoName.indexOf("⟦") >= 0, "cell names are built from the catalogue: " + pseudoName)
            check(I18n.tr("error.backendExited", { code: 3 }).indexOf("3") > 0, "pseudo keeps placeholders")
            I18n.setLocale("en")
            check(main.errorMessage === "No audio output — running silently", "back to English")
            // Captions are lifted until they read on the ground behind them.
            var Theme = Winkel.Theme
            check(Theme.contrast(Theme.color.captionOnSurface, Theme.color.surface) >= 4.5,
                  "the card's captions must pass 4.5:1, got " + Theme.contrast(Theme.color.captionOnSurface, Theme.color.surface).toFixed(2))
            check(Theme.contrast(Theme.color.caption, Theme.color.background) >= 4.5,
                  "the window's captions must pass 4.5:1, got " + Theme.contrast(Theme.color.caption, Theme.color.background).toFixed(2))
            // The worst theme installed here, rose-pine: muted #6E6A86 on its
            // card #191724 reads at 1.32:1 and must come back readable.
            var lifted = Theme.readable("#6E6A86", "#191724", "#E0DEF4", 4.5)
            check(Theme.contrast(lifted, "#191724") >= 4.5, "a faint theme must lift to 4.5:1")
            // A caption that already passes keeps the theme's own colour.
            check(Theme.contrast(Theme.readable("#E0DEF4", "#191724", "#FFFFFF", 4.5), "#191724")
                  === Theme.contrast("#E0DEF4", "#191724"), "a readable caption is left alone")
            console.log("PASS: frontend voices, loading, silent warning, save, meter limit, subdivision, catalogue, i18n, contrast")
            Qt.quit()
        }
    }
    Timer { interval: 5000; running: true; onTriggered: Qt.quit() }
}
