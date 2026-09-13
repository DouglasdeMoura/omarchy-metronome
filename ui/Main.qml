import QtQuick

// Pulse's one screen. Everything musical lives here: the tempo marking, the
// ring with the beat in its middle, the transport, the meter. The backend
// owns time; this file only draws what its events say and pushes what its
// controls move.
Item {
    id: root

    property var backend: null

    signal closeRequested()

    // --- the state the backend mirrors ---
    property bool running: false
    property real bpm: 120
    property int beats: 4
    property int denominator: 4
    // Per-beat voice: 0 silent, 1 low tone, 2 medium tone, 3 high tone.
    // Twelve slots, one per beat position, so a pattern survives a change of
    // meter.
    property var voices: [3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    property int currentBeat: -1
    property int totalBeats: 0
    property string errorMessage: ""

    property var tapTimes: []
    property bool tsOpen: false

    // The classical markings, as bands: what the beat is relative to. The
    // bounds are the usual metronome tables, one band per name.
    readonly property var tempoBands: [
        { name: "Larghissimo", max: 20 },
        { name: "Grave", max: 40 },
        { name: "Largo", max: 60 },
        { name: "Adagio", max: 76 },
        { name: "Andante", max: 108 },
        { name: "Moderato", max: 120 },
        { name: "Allegretto", max: 156 },
        { name: "Allegro", max: 176 },
        { name: "Vivace", max: 200 },
        { name: "Presto", max: 240 },
        { name: "Prestissimo", max: 9999 }
    ]

    readonly property int tempoBand: {
        for (var i = 0; i < tempoBands.length; i++)
            if (bpm <= tempoBands[i].max) return i
        return tempoBands.length - 1
    }
    readonly property string tempoName: tempoBands[tempoBand].name

    // The first state line arrives before this item does; until it has been
    // applied, no control pushes its own value back down the wire.
    property bool loading: true

    Component.onCompleted: {
        backend.hello()
        rebuildRing()
        loading = false
    }

    function clampBpm(v) {
        return Math.min(400, Math.max(10, v))
    }

    function setBpm(v) {
        v = clampBpm(Math.round(v))
        if (v !== root.bpm) root.bpm = v
        hero.text = root.bpm
    }

    function pushParams() {
        if (!root.backend || root.loading) return
        root.backend.params({ bpm: root.bpm, beats: root.beats, denominator: root.denominator, voices: root.voices })
    }

    function pushSave() {
        if (!root.backend || root.loading) return
        saveTimer.restart()
    }

    Timer {
        id: saveTimer
        interval: 500
        onTriggered: root.backend.save({
            bpm: root.bpm, beats: root.beats, denominator: root.denominator, voices: root.voices
        })
    }

    onBpmChanged: { pushParams(); pushSave() }
    onBeatsChanged: { pushParams(); pushSave(); root.rebuildRing() }

    // Every open/close path rebuilds the ring — the button, Enter on the
    // focused signature, Escape — so Tab always cycles the view in front.
    onTsOpenChanged: {
        root.focusIndex = -1
        root.rebuildRing()
        if (root.tsOpen && root.tabbing) root.focusIndex = 0
        root.updateFocusFrame()
        if (!root.tsOpen) tabbing = false
    }
    onDenominatorChanged: { pushParams(); pushSave() }
    onVoicesChanged: { pushParams(); pushSave() }

    // Click a beat rectangle to raise its fill: silent, low, medium, high.
    function cycleVoice(i) {
        var next = root.voices.slice()
        next[i] = (next[i] + 1) % 4
        root.voices = next
    }

    function tap() {
        var now = Date.now()
        if (root.tapTimes.length > 0 && now - root.tapTimes[root.tapTimes.length - 1] > 2000)
            root.tapTimes = []
        root.tapTimes.push(now)
        if (root.tapTimes.length > 6) root.tapTimes.shift()
        if (root.tapTimes.length >= 2) {
            var sum = 0
            for (var i = 1; i < root.tapTimes.length; i++)
                sum += root.tapTimes[i] - root.tapTimes[i - 1]
            setBpm(60000 / (sum / (root.tapTimes.length - 1)))
        }
    }

    Connections {
        target: root.backend

        function onStateReceived(bpm, beats, denominator, voices, volume) {
            root.loading = true
            root.bpm = bpm
            root.beats = beats
            root.denominator = denominator
            if (voices.length === 12) root.voices = voices
            hero.text = Math.round(bpm)
            root.loading = false
        }

        function onReadyReceived(device, rate, silent) {
            // The device's own identity is the system's business, not a label
            // for the window; only its answer clears a standing error.
            root.errorMessage = ""
        }

        function onStarted() {
            root.running = true
            root.totalBeats = 0
        }

        function onBeat(beat, kind) {
            root.currentBeat = beat
            root.totalBeats += 1
        }

        function onStopped(totalBeats) {
            root.running = false
            root.currentBeat = -1
            root.totalBeats = totalBeats
        }

        function onFailed(message) {
            root.errorMessage = message
        }
    }

    // --- keyboard, the first-class input ---
    // --- the keyboard focus ring: Tab cycles the view's clickable things,
    // enter/space clicks the focused one, arrows step the ones that step.
    property var ring: []
    property int focusIndex: -1
    // The focus frame belongs to tab navigation alone: clicks and direct
    // shortcuts move where Tab continues from, without drawing the frame.
    property bool tabbing: false

    function currentEntry() {
        return (focusIndex >= 0 && focusIndex < ring.length) ? ring[focusIndex] : null
    }

    function ringIndex(item) {
        rebuildRing()
        for (var i = 0; i < ring.length; i++)
            if (ring[i].item === item) return i
        return -1
    }

    function cycleFocus(back) {
        tabbing = true
        rebuildRing()
        var n = ring.length
        if (n === 0) { focusIndex = -1; updateFocusFrame(); return }
        var i = focusIndex + (back ? -1 : 1)
        if (i >= n) i = -1
        if (i < -1) i = n - 1
        focusIndex = i
        updateFocusFrame()
    }

    function rebuildRing() {
        if (tsOpen) rebuildDialogRing()
        else rebuildMainRing()
        if (focusIndex >= ring.length) focusIndex = -1
        updateFocusFrame()
    }

    function rebuildMainRing() {
        var r = []
        r.push({ item: chrome.closeItem, activate: function () { root.closeRequested() } })
        for (var i = 0; i < root.beats; i++) {
            (function (idx) {
                var it = metersRepeater.itemAt(idx)
                if (it) r.push({ item: it, activate: function () { root.cycleVoice(idx) } })
            })(i)
        }
        r.push({ item: bpmMinusBtn, activate: function () { root.setBpm(root.bpm - 1) },
                 step: function (d) { root.setBpm(root.bpm + d) } })
        r.push({ item: bpmPlusBtn, activate: function () { root.setBpm(root.bpm + 1) },
                 step: function (d) { root.setBpm(root.bpm + d) } })
        r.push({ item: play, activate: function () { root.backend.toggle() } })
        r.push({ item: tsButton, activate: function () { root.tsOpen = true } })
        r.push({ item: tapButton, activate: function () { root.tap() } })
        ring = r
    }

    function rebuildDialogRing() {
        var r = []
        for (var i = 0; i < presetsRepeater.count; i++) {
            (function (idx) {
                var it = presetsRepeater.itemAt(idx)
                if (it) r.push({
                    item: it,
                    activate: function () { it.activatePreset() },
                    step: function (d) {
                        var j = Math.min(presetsRepeater.count - 1, Math.max(0, idx + d))
                        if (j !== idx && presetsRepeater.itemAt(j)) presetsRepeater.itemAt(j).activatePreset()
                    }
                })
            })(i)
        }
        r.push({ item: numWheel,
                 step: function (d) {
                     tsPanel.draftBeats = Math.min(16, Math.max(1, tsPanel.draftBeats + d))
                     numWheel.select(tsPanel.draftBeats)
                 } })
        r.push({ item: denWheel,
                 step: function (d) {
                     var ladder = [1, 2, 4, 8]
                     var i = ladder.indexOf(tsPanel.draftDenominator)
                     tsPanel.draftDenominator = ladder[Math.min(3, Math.max(0, i + d))]
                     denWheel.select(tsPanel.draftDenominator)
                 } })
        r.push({ item: cancelBtn, activate: function () { root.tsOpen = false } })
        r.push({ item: okBtn, activate: function () {
            root.beats = tsPanel.draftBeats
            root.denominator = tsPanel.draftDenominator
            root.tsOpen = false
        } })
        ring = r
    }

    function syncFocusToPoint(p) {
        tabbing = false
        rebuildRing()
        for (var i = 0; i < ring.length; i++) {
            var it = ring[i].item
            if (!it || !it.visible) continue
            var tl = it.mapToItem(root, 0, 0)
            if (p.x >= tl.x - 3 && p.x <= tl.x + it.width + 3
                    && p.y >= tl.y - 3 && p.y <= tl.y + it.height + 3) {
                focusIndex = i
                updateFocusFrame()
                return
            }
        }
        focusIndex = -1
        updateFocusFrame()
    }

    function updateFocusFrame() {
        var e = tabbing ? currentEntry() : null
        if (!e || !e.item) { focusFrame.visible = false; return }
        var p = e.item.mapToItem(focusFrame.parent, 0, 0)
        focusFrame.x = p.x - 3
        focusFrame.y = p.y - 3
        focusFrame.width = e.item.width + 6
        focusFrame.height = e.item.height + 6
        focusFrame.visible = true
    }

    Keys.onPressed: function (event) {
        // The dialog owns the keyboard while it is open.
        if (root.tsOpen) {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                root.cycleFocus(event.modifiers & Qt.ShiftModifier)
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                root.tsOpen = false
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                var eOk = root.currentEntry()
                if (eOk && eOk.activate) eOk.activate()
                event.accepted = true
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down
                    || event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                var eStep = root.currentEntry()
                if (eStep && eStep.step) eStep.step((event.key === Qt.Key_Up || event.key === Qt.Key_Right) ? 1 : -1)
                event.accepted = true
            } else {
                event.accepted = true
            }
            return
        }

        // Tab cycles the main view's clickable things.
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.cycleFocus(event.modifiers & Qt.ShiftModifier)
            event.accepted = true
            return
        }

        // A focused control answers enter/space and the arrows first — but
        // only while tab navigation is in play.
        var entry = tabbing ? root.currentEntry() : null
        if (entry) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                if (entry.activate) entry.activate()
                event.accepted = true
                return
            }
            if (entry.step && (event.key === Qt.Key_Up || event.key === Qt.Key_Down
                    || event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                entry.step((event.key === Qt.Key_Up || event.key === Qt.Key_Right) ? 1 : -1)
                event.accepted = true
                return
            }
        }

        if (event.key === Qt.Key_Space) {
            root.backend.toggle()
            root.focusIndex = root.ringIndex(play)
            root.updateFocusFrame()
            tabbing = false
            event.accepted = true
        } else if (event.key === Qt.Key_T) {
            root.tap()
            root.focusIndex = root.ringIndex(tapButton)
            root.updateFocusFrame()
            tabbing = false
            event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            setBpm(root.bpm + (event.modifiers & Qt.ShiftModifier ? 5 : 1))
            event.accepted = true
        } else if (event.key === Qt.Key_Down) {
            setBpm(root.bpm - (event.modifiers & Qt.ShiftModifier ? 5 : 1))
            event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
            setBpm(root.bpm + 10)
            event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
            setBpm(root.bpm - 10)
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            if (root.running) root.backend.stop()
            event.accepted = true
        } else if (event.key === Qt.Key_Q && (event.modifiers & Qt.ControlModifier)) {
            root.closeRequested()
            event.accepted = true
        } else if (event.key === Qt.Key_1 || event.key === Qt.Key_2
                || event.key === Qt.Key_4 || event.key === Qt.Key_8) {
            root.denominator = event.key - Qt.Key_0
            root.focusIndex = root.ringIndex(tsButton)
            root.updateFocusFrame()
            tabbing = false
            event.accepted = true
        }
    }

    // --- layout ---
    // Three fixed rails: the chrome on top, the status strip pinned to the
    // bottom, and the instrument itself centred in what is left over, so a
    // tiled window and a floating one both read as composed, not stretched.
    ChromeBar {
        id: chrome
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        onClosed: root.closeRequested()
    }

    StatusStrip {
        id: status
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        totalBeats: root.totalBeats
        error: root.errorMessage
    }

    Item {
        anchors.top: chrome.bottom
        anchors.bottom: status.top
        anchors.left: parent.left
        anchors.right: parent.right

        Column {
            id: content
            width: Math.min(parent.width, Theme.space(320))
            spacing: Theme.space(16)
            x: (parent.width - width) / 2
            y: Math.max(Theme.space(16), (parent.height - height) / 2)

            // --- per-beat voices, on top of the circle: click to raise ---
            // Empty is silence; one, two or three filled bars are the low,
            // medium and high tick.
            Row {
                id: meters
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space(8)
                // Twelve meters still have to fit the column, so the boxes
                // give up width before the gaps do.
                readonly property int rectWidth: Math.min(
                    Theme.space(26),
                    Math.floor((Theme.space(320) - (root.beats - 1) * spacing) / root.beats))

                Repeater {
                    id: metersRepeater
                    model: root.beats

                    Rectangle {
                        id: pick
                        readonly property int voice: root.voices[index]
                        readonly property bool isNow: root.running && root.currentBeat === index
                        width: meters.rectWidth
                        height: Theme.space(38)
                        radius: 0
                        color: "transparent"
                        border.width: isNow ? 2 : 1
                        border.color: isNow ? Theme.color.accent : Theme.color.line

                        // The bars stack from the bottom, so the fill reads
                        // as a level: one bar low, three high.
                        Column {
                            anchors.centerIn: parent
                            spacing: Theme.space(1)

                            Repeater {
                                model: 3

                                Rectangle {
                                    readonly property int fillOrder: 2 - index
                                    width: pick.width - Theme.space(8)
                                    height: (pick.height - Theme.space(8)) / 3
                                    radius: 0
                                    color: fillOrder < pick.voice ? Theme.color.accent : Theme.color.lineSoft
                                }
                            }
                        }

                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.cycleVoice(index) }
                    }
                }
            }

            // --- the tempo: marking on top, number between the steppers ---
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.tempoName
                color: Theme.color.muted
                font.family: Theme.font.family
                font.pixelSize: Theme.font.caption
                font.capitalization: Font.AllUppercase
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space(16)

                Rectangle {
                    id: bpmMinusBtn
                    width: Theme.space(30)
                    height: Theme.space(30)
                    radius: 0
                    anchors.verticalCenter: parent.verticalCenter
                    color: bpmMinus.pressed ? Qt.alpha(Theme.color.accent, 0.18) : Theme.color.lineSoft
                    border.width: 1
                    border.color: Theme.color.lineSoft

                    Text {
                        anchors.centerIn: parent
                        text: "−"
                        color: Theme.color.foreground
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.body
                    }

                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: bpmMinus; onTapped: root.setBpm(root.bpm - 1) }
                }

                Column {
                    spacing: Theme.space(2)

                    TextInput {
                        id: hero
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Math.round(root.bpm)
                        color: root.running ? Theme.color.accent : Theme.color.foreground
                        selectionColor: Qt.alpha(Theme.color.accent, 0.35)
                        selectedTextColor: Theme.color.background
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.hero
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        validator: IntValidator { bottom: 1; top: 4000 }
                        cursorVisible: activeFocus

                        Keys.onPressed: function (event) {
                            if (event.key === Qt.Key_Up) {
                                root.setBpm(root.bpm + (event.modifiers & Qt.ShiftModifier ? 5 : 1))
                                event.accepted = true
                            } else if (event.key === Qt.Key_Down) {
                                root.setBpm(root.bpm - (event.modifiers & Qt.ShiftModifier ? 5 : 1))
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.forceActiveFocus()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Escape) {
                                hero.text = Math.round(root.bpm)
                                root.forceActiveFocus()
                                event.accepted = true
                            }
                        }

                        onEditingFinished: {
                            var v = parseInt(hero.text)
                            if (isNaN(v)) {
                                hero.text = Math.round(root.bpm)
                            } else {
                                root.setBpm(v)
                                hero.text = Math.round(root.bpm)
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: hero.forceActiveFocus()
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "BPM"
                        color: Theme.color.muted
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.caption
                    }
                }

                Rectangle {
                    id: bpmPlusBtn
                    width: Theme.space(30)
                    height: Theme.space(30)
                    radius: 0
                    anchors.verticalCenter: parent.verticalCenter
                    color: bpmPlus.pressed ? Qt.alpha(Theme.color.accent, 0.18) : Theme.color.lineSoft
                    border.width: 1
                    border.color: Theme.color.lineSoft

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: Theme.color.foreground
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.body
                    }

                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: bpmPlus; onTapped: root.setBpm(root.bpm + 1) }
                }
            }

            // --- the transport: one prominent circle, dead centre ---
            Rectangle {
                id: play
                width: Theme.space(68)
                height: width
                anchors.horizontalCenter: parent.horizontalCenter
                radius: width / 2
                color: root.running ? Theme.color.accent : Qt.alpha(Theme.color.accent, 0.16)
                border.width: 1
                border.color: root.running ? Theme.color.accent : Qt.alpha(Theme.color.accent, 0.45)
                scale: playTap.pressed && !Theme.reducedMotion ? 0.94 : 1

                Behavior on scale {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 120 }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.running ? "■" : "▶"
                    color: root.running ? Theme.color.background : Theme.color.accent
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.heading + 4
                }

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    id: playTap
                    onTapped: root.backend.toggle()
                }
            }

            // --- the time signature: one button, the editor opens over all ---
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space(10)

                Rectangle {
                    id: tsButton
                    width: Theme.space(76)
                    height: Theme.space(38)
                    color: tsTap.pressed ? Qt.alpha(Theme.color.accent, 0.18) : Theme.color.lineSoft
                    border.width: 1
                    border.color: root.tsOpen ? Theme.color.accent : Theme.color.line

                    Text {
                        anchors.centerIn: parent
                        text: root.beats + "/" + root.denominator
                        color: Theme.color.foreground
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.subtitle
                        font.weight: Font.DemiBold
                    }

                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        id: tsTap
                        onTapped: {
                            root.tsOpen = !root.tsOpen
                            root.focusIndex = -1
                            root.rebuildRing()
                        }
                    }
                }

                // Tap tempo rides beside the signature, a secondary control
                // beside the transport it serves.
                Rectangle {
                    id: tapButton
                    width: Theme.space(60)
                    height: Theme.space(30)
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 0
                    color: tapTap.pressed ? Qt.alpha(Theme.color.accent, 0.18) : Theme.color.lineSoft
                    border.width: 1
                    border.color: Theme.color.lineSoft

                    Text {
                        anchors.centerIn: parent
                        text: "Tap"
                        color: Theme.color.foreground
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.bodySmall
                    }

                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        id: tapTap
                        onTapped: root.tap()
                    }
                }
            }

            Text {
                width: parent.width
                text: "space play · arrows tempo · t tap · esc stop"
                color: Theme.color.muted
                opacity: 0.7
                font.family: Theme.font.family
                font.pixelSize: Theme.font.caption
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }

        // --- the time signature editor, over everything while open ---
        // The wheels spin a draft; ok commits it to the metronome, cancel —
        // or a click outside — throws the draft away.
        MouseArea {
            anchors.fill: parent
            visible: root.tsOpen
            onClicked: root.tsOpen = false
        }

        Rectangle {
            id: tsPanel

            property int draftBeats: root.beats
            property int draftDenominator: root.denominator

            anchors.centerIn: parent
            visible: root.tsOpen
            width: Theme.space(296)
            height: tsColumn.implicitHeight + Theme.space(36)
            color: Theme.color.surface
            border.width: 1
            border.color: Theme.color.line

            // The panel's own click-swallowing surface: a press between the
            // controls belongs to the dialog, never to the cancel-scrim.
            MouseArea { anchors.fill: parent }

            onVisibleChanged: {
                if (!visible) {
                    root.forceActiveFocus()
                    root.focusIndex = -1
                    root.rebuildRing()
                    return
                }
                draftBeats = root.beats
                draftDenominator = root.denominator
                numWheel.select(draftBeats)
                denWheel.select(draftDenominator)
            }

            // The panel can be born visible; the wheels need their first spin
            // at completion either way.
            Component.onCompleted: {
                draftBeats = root.beats
                draftDenominator = root.denominator
                numWheel.select(draftBeats)
                denWheel.select(draftDenominator)
                // Born visible (a state file's dialog, a test): the shell's
                // own startup focus pass runs after this, so the claim is
                // deferred to land last.
                Qt.callLater(function () { forceActiveFocus() })
            }

            Column {
                id: tsColumn
                anchors.centerIn: parent
                spacing: Theme.space(12)

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "TIME SIGNATURE"
                    color: Theme.color.muted
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.caption
                }

                // The common meters, one click each.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.space(5)

                    Repeater {
                        id: presetsRepeater
                        model: ["2/4", "3/4", "4/4", "5/4", "6/8", "7/8", "12/8"]

                        Rectangle {
                            readonly property var parts: modelData.split("/")
                            readonly property bool chosen: tsPanel.draftBeats === +parts[0]
                                                           && tsPanel.draftDenominator === +parts[1]
                            width: presetLabel.implicitWidth + Theme.space(12)
                            height: Theme.space(24)
                            color: chosen ? Qt.alpha(Theme.color.accent, 0.25) : Theme.color.lineSoft
                            border.width: chosen ? 2 : 1
                            border.color: chosen ? Theme.color.accent : Theme.color.line

                            Text {
                                id: presetLabel
                                anchors.centerIn: parent
                                text: modelData
                                color: parent.chosen ? Theme.color.accent : Theme.color.foreground
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.caption
                            }

                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    tsPanel.draftBeats = +parent.parts[0]
                                    tsPanel.draftDenominator = +parent.parts[1]
                                    numWheel.select(tsPanel.draftBeats)
                                    denWheel.select(tsPanel.draftDenominator)
                                }
                            }
                        }
                    }
                }

                // The wheels: drag, scroll, or click; the middle is the draft.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.space(6)

                    WheelColumn {
                        id: numWheel
                        values: {
                            var v = []
                            for (var i = 1; i <= 16; i++) v.push(i)
                            return v
                        }
                        onPickedChanged: tsPanel.draftBeats = picked
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "/"
                        color: Theme.color.muted
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.heading
                    }

                    WheelColumn {
                        id: denWheel
                        values: [1, 2, 4, 8]
                        onPickedChanged: tsPanel.draftDenominator = picked
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.space(10)

                    Rectangle {
                        id: cancelBtn
                        width: Theme.space(90)
                        height: Theme.space(30)
                        color: tsCancel.pressed ? Qt.alpha(Theme.color.accent, 0.18) : Theme.color.lineSoft
                        border.width: 1
                        border.color: Theme.color.line

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.color.foreground
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.bodySmall
                        }

                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { id: tsCancel; onTapped: root.tsOpen = false }
                    }

                    Rectangle {
                        id: okBtn
                        width: Theme.space(90)
                        height: Theme.space(30)
                        color: tsOk.pressed ? Qt.alpha(Theme.color.accent, 0.8) : Theme.color.accent

                        Text {
                            anchors.centerIn: parent
                            text: "OK"
                            color: Theme.color.background
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.bodySmall
                            font.weight: Font.DemiBold
                        }

                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            id: tsOk
                            onTapped: {
                                root.beats = tsPanel.draftBeats
                                root.denominator = tsPanel.draftDenominator
                                root.tsOpen = false
                            }
                        }
                    }
                }
            }

    }
}
    // Taps anywhere keep the ring in step with the mouse: the tap is
    // hit-tested against the ring's own controls.
    TapHandler {
        id: clickSync
        onTapped: function (eventPoint) { root.syncFocusToPoint(eventPoint.position) }
    }

    Rectangle {
        id: focusFrame
        visible: false
        color: "transparent"
        radius: 0
        border.width: 2
        border.color: Theme.color.accent
    }
}
