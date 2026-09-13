import Quickshell
import QtQuick
import "ui" as Pulse

ShellRoot {
    Item {
        id: backend
        property var saved: null
        property var patched: null
        signal stateReceived(real bpm, int beats, int denominator, var voices, real volume)
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
            backend.stateReceived(120, 16, 4, [3,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1], 0.8)
            check(!main.loading, "state must release loading gate")
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
            console.log("PASS: frontend voices, loading, silent warning, save, meter limit")
            Qt.quit()
        }
    }
    Timer { interval: 5000; running: true; onTriggered: Qt.quit() }
}
