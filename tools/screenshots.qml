import Quickshell
import QtQuick
import "WINKEL_UI_DIR" as Winkel

// The README's screenshots: the main view, the time signature editor and the
// subdivision editor, at the window's own 382x661, over a stub backend holding
// the state the app opens with. tools/screenshots.sh drives this once per
// theme; see docs/releasing.md.
ShellRoot {
    id: app

    // Backend.qml's surface, without the process: enough for Main to bind to.
    Item {
        id: backend
        signal stateReceived(real bpm, int beats, int denominator, var voices, real volume, int subdivision, int subpattern, int subshape)
        signal readyReceived(string device, int rate, bool silent)
        signal started()
        signal beat(int beat, string kind)
        signal stopped(int totalBeats)
        signal failed(string message)
        function hello() {}
        function params(f) {}
        function save(f) {}
        function toggle() {}
        function stop() {}
    }

    Window {
        visible: true
        width: 382
        height: 661
        Rectangle {
            id: ground
            anchors.fill: parent
            color: Winkel.Theme.color.background
            Winkel.Main { id: main; anchors.fill: parent; backend: backend }
        }
    }

    // Each shot opens what it shows the way the buttons do.
    readonly property var steps: [
        { name: "main", act: function () {} },
        { name: "time-signature", act: function () { main.tsOpen = true } },
        { name: "subdivision", act: function () { main.tsOpen = false; main.subOpen = true } }
    ]
    property int at: 0

    function run() {
        if (at >= steps.length) { console.log("SHOTS done"); Qt.quit(); return }
        var step = steps[at++]
        step.act()
        main.focusIndex = -1
        main.rebuildRing()
        // One frame for the change to land, one for it to settle.
        Qt.callLater(function () { Qt.callLater(function () {
            ground.grabToImage(function (result) {
                result.saveToFile(Quickshell.env("SHOT_DIR") + "/" + Quickshell.env("SHOT_THEME") + "-" + step.name + ".png")
                run()
            })
        }) })
    }

    // The state the app opens with: 80 bpm, 4/4, the first voice accented.
    Timer {
        interval: 600
        running: true
        onTriggered: { backend.stateReceived(80, 4, 4, [3,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1], 0.8, 1, 1, 1); run() }
    }
    // A floor under a run that never reaches Qt.quit().
    Timer { interval: 25000; running: true; onTriggered: Qt.quit() }
}
