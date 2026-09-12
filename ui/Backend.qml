import Quickshell
import Quickshell.Io
import QtQuick

// The backend bridge, Flea's shape exactly: one child process speaking one
// json object per line both ways, a queue for the words that arrive before
// the spawn finishes, and one signal per event the protocol defines.
Item {
    id: root

    signal stateReceived(real bpm, int beats, int denominator, var voices, real volume)
    signal readyReceived(string device, int rate, bool silent)
    signal started()
    signal beat(int beat, string kind)
    signal stopped(int totalBeats)
    signal failed(string message)
    signal quitReady()

    readonly property bool running: child.running

    // A write before the child is spawned is dropped silently, so an early
    // request waits here.
    property var pending: []
    property bool queueing: true

    // A quit is in flight, so the child's exit is the close the window asked
    // for, not a backend that died.
    property bool quitting: false

    // Everything the UI sends goes through here, so the protocol has exactly
    // one author.
    function send(object) {
        var line = JSON.stringify(object) + "\n"
        if (root.queueing) {
            root.pending.push(line)
            return
        }
        if (!child.running) {
            root.failed("the backend is not running")
            return
        }
        child.write(line)
    }

    function hello() { root.send({ c: "hello" }) }
    function start() { root.send({ c: "start" }) }
    function stop() { root.send({ c: "stop" }) }
    function toggle() { root.send({ c: "toggle" }) }

    function params(fields) {
        var message = { c: "params" }
        for (var k in fields) message[k] = fields[k]
        root.send(message)
    }

    function save(fields) {
        var message = { c: "save" }
        for (var k in fields) message[k] = fields[k]
        root.send(message)
    }

    // The shell's exit gate: the backend answers quitready once it has
    // stopped the clock, and only then does the window close.
    function quit() {
        if (root.quitting) return
        root.quitting = true
        if (root.queueing || !child.running) {
            root.quitReady()
            return
        }
        root.send({ c: "quit" })
    }

    // Sample input: {"t":"state","bpm":120,"beats":4,"subdiv":1,"accent":true,"volume":0.8}
    // Sample input: {"t":"ready","device":"default","rate":44100,"silent":false}
    // Sample input: {"t":"beat","beat":0,"sub":2,"kind":"sub"}
    // Sample input: {"t":"stopped","beats":12}
    function receive(line) {
        if (!line || line.length === 0) return
        var message = null
        try {
            message = JSON.parse(line)
        } catch (e) {
            root.failed("the backend sent a line this build cannot read")
            return
        }
        if (message.t === "state") {
            root.stateReceived(message.bpm, message.beats, message.denominator,
                               message.voices || [], message.volume)
        } else if (message.t === "ready") {
            root.readyReceived(message.device || "", message.rate || 0, message.silent === true)
        } else if (message.t === "started") {
            root.started()
        } else if (message.t === "beat") {
            root.beat(message.beat || 0, message.kind || "low")
        } else if (message.t === "stopped") {
            root.stopped(message.beats || 0)
        } else if (message.t === "error") {
            root.failed(message.msg || "unknown backend error")
        } else if (message.t === "quitready") {
            root.quitReady()
        }
    }

    Process {
        id: child
        // PULSE_BIN is the dev seam, the way gui.rs hands itself over.
        command: [Quickshell.env("PULSE_BIN") || "pulse", "--backend"]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) { root.receive(data) }
        }

        onStarted: {
            root.queueing = false
            for (var i = 0; i < root.pending.length; i++) {
                child.write(root.pending[i])
            }
            root.pending = []
        }

        // A spawn that fails raises runningChanged and never exited, so the
        // window gets a message instead of a metronome that never answers.
        onRunningChanged: {
            if (root.queueing && !child.running) {
                root.queueing = false
                root.pending = []
                root.failed("the backend could not be started")
            }
        }

        onExited: function (exitCode, exitStatus) {
            if (root.quitting) {
                root.quitReady()
                return
            }
            root.failed("the backend exited with code " + exitCode)
        }
    }
}
