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
    // Sixteen slots, one per beat position, so a pattern survives a change of
    // meter.
    property var voices: [3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    property int currentBeat: -1
    property string errorMessage: ""

    property var tapTimes: []
    property bool tsOpen: false
    property bool keysOpen: false

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

    function flushSave() {
        if (!saveTimer.running || root.loading) return
        saveTimer.stop()
        root.backend.save({
            bpm: root.bpm, beats: root.beats, denominator: root.denominator, voices: root.voices
        })
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
            if (voices.length === 16) root.voices = voices
            hero.text = Math.round(bpm)
            root.loading = false
        }

        function onReadyReceived(device, rate, silent) {
            root.errorMessage = silent ? "No audio output — running silently" : ""
        }

        function onStarted() {
            root.running = true
        }

        function onBeat(beat, kind) {
            root.currentBeat = beat
        }

        function onStopped(totalBeats) {
            root.running = false
            root.currentBeat = -1
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
        // The keys sheet owns the keyboard while it is open: esc or ? closes
        // it, and nothing else reaches the instrument underneath.
        if (root.keysOpen) {
            if (event.key === Qt.Key_Escape || event.text === "?") root.keysOpen = false
            event.accepted = true
            return
        }

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

        if (event.text === "?") {
            root.keysOpen = true
            event.accepted = true
        } else if (event.key === Qt.Key_Space) {
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
    // Two fixed rails: the chrome on top and the instrument itself centred
    // in what is left over, so a tiled window and a floating one both read
    // as composed, not stretched.
    ChromeBar {
        id: chrome
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        onClosed: root.closeRequested()
    }

    Item {
        anchors.top: chrome.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right

        Column {
            id: content
            width: Math.min(parent.width, Theme.space(320))
            spacing: Theme.space(24)
            x: (parent.width - width) / 2
            y: Math.max(Theme.space(16), (parent.height - height) / 2)

            // --- per-beat voices, on top of the circle: click to raise ---
            // Empty is silence; one, two or three filled bars are the low,
            // medium and high tick.
            Row {
                id: meters
                anchors.horizontalCenter: parent.horizontalCenter
                // Sixteen meters still have to fit the column: past twelve
                // the gaps close up first, then the boxes give up width.
                spacing: Theme.space(root.beats > 12 ? 4 : 8)
                readonly property int rectWidth: Math.min(
                    Theme.space(26),
                    Math.floor((Theme.space(320) - (root.beats - 1) * spacing) / root.beats))
                // Each bar is a golden rectangle, lying down; the beat's
                // height follows from three of them and the gaps between.
                readonly property int barWidth: rectWidth - Theme.space(8)
                readonly property int barHeight: Math.round(barWidth / 1.618)
                readonly property int barGap: Theme.space(4)

                Repeater {
                    id: metersRepeater
                    model: root.beats

                    Rectangle {
                        id: pick
                        readonly property int voice: root.voices[index]
                        readonly property bool isNow: root.running && root.currentBeat === index
                        width: meters.rectWidth
                        height: 3 * meters.barHeight + 2 * meters.barGap + Theme.space(8)
                        radius: 0
                        color: "transparent"

                        // The bars stack from the bottom, so the fill reads
                        // as a level: one bar low, three high. No frame: the
                        // playing beat is the one whose empty bars light up.
                        Column {
                            anchors.centerIn: parent
                            spacing: meters.barGap

                            Repeater {
                                model: 3

                                Rectangle {
                                    readonly property int fillOrder: 2 - index
                                    width: meters.barWidth
                                    height: meters.barHeight
                                    radius: 0
                                    color: fillOrder < pick.voice ? Theme.color.accent
                                         : pick.isNow ? Theme.color.line : Theme.color.lineSoft
                                }
                            }
                        }

                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.cycleVoice(index) }
                    }
                }
            }

            // --- the tempo: marking on top, the numeral between two steppers
            // that sit on its own centre line, the unit beneath ---
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space(4)

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
                    spacing: Theme.space(12)

                    DialogButton {
                        id: bpmMinusBtn
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.space(36)
                        height: Theme.space(36)
                        label: "−"
                        pixelSize: Theme.font.heading
                        framed: false
                        fillColor: Theme.color.lineSoft
                        onActivated: root.setBpm(root.bpm - 1)
                    }

                    TextInput {
                        id: hero
                        // Room for four digits at the hero size, so the
                        // steppers hold still while the number changes.
                        width: Theme.space(150)
                        text: Math.round(root.bpm)
                        color: Theme.color.foreground
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

                    DialogButton {
                        id: bpmPlusBtn
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.space(36)
                        height: Theme.space(36)
                        label: "+"
                        pixelSize: Theme.font.heading
                        framed: false
                        fillColor: Theme.color.lineSoft
                        onActivated: root.setBpm(root.bpm + 1)
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

            // --- the transport: the one accent on the view, dead centre.
            // An outlined circle at rest; solid while the metronome runs ---
            Rectangle {
                id: play
                width: Theme.space(88)
                height: width
                anchors.horizontalCenter: parent.horizontalCenter
                radius: width / 2
                color: root.running ? Theme.color.accent : "transparent"
                border.width: 2 * Theme.spacing.hairline
                border.color: Theme.color.accent
                scale: playTap.pressed && !Theme.reducedMotion ? 0.96 : 1

                Behavior on scale {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.running ? "■" : "▶"
                    color: root.running ? Theme.color.background : Theme.color.accent
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.display
                }

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    id: playTap
                    onTapped: root.backend.toggle()
                }
            }

            // --- the meter and tap tempo: two equal buttons under the
            // transport, the steppers' height so the transport alone stands
            // tall; the meter's frame lights while its editor is open ---
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space(12)

                DialogButton {
                    id: tsButton
                    width: Theme.space(84)
                    height: Theme.space(36)
                    label: root.beats + "/" + root.denominator
                    pixelSize: Theme.font.body
                    weight: Font.DemiBold
                    primary: root.tsOpen
                    onActivated: {
                        root.tsOpen = !root.tsOpen
                        root.focusIndex = -1
                        root.rebuildRing()
                    }
                }

                DialogButton {
                    id: tapButton
                    width: Theme.space(84)
                    height: Theme.space(36)
                    label: "Tap"
                    pixelSize: Theme.font.body
                    onActivated: root.tap()
                }
            }

            // Only when something is wrong: the error under the controls, in
            // urgent ink, the one place the window says so.
            Text {
                width: parent.width
                visible: root.errorMessage.length > 0
                text: root.errorMessage
                color: Theme.color.urgent
                font.family: Theme.font.family
                font.pixelSize: Theme.font.caption
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
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
            height: tsColumn.implicitHeight + 2 * Theme.spacing.rowPaddingX
            // Flea's dialog card: the theme's dark ground behind a muted hairline.
            color: Theme.color.surface
            border.width: Theme.spacing.hairline
            border.color: Theme.color.muted
            radius: Theme.cornerRadius

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
                width: parent.width
                anchors.top: parent.top
                anchors.topMargin: Theme.spacing.rowPaddingX
                spacing: 0

                // Flea's dialog header: the title sits at the card's left
                // padding on a hairline rule, and the body hangs below it.
                Text {
                    width: parent.width
                    leftPadding: Theme.spacing.rowPaddingX
                    rightPadding: Theme.spacing.rowPaddingX
                    bottomPadding: Theme.spacing.gap
                    text: "TIME SIGNATURE"
                    color: Theme.color.muted
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.caption

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Theme.spacing.hairline
                        color: Theme.color.muted
                        opacity: 0.4
                    }
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.space(12)
                    topPadding: Theme.space(12)
                    bottomPadding: Theme.space(12)

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
                }

                // Flea's action row: Cancel then the primary, flush with the
                // card's right padding.
                Item {
                    width: parent.width
                    height: Math.max(cancelBtn.height, okBtn.height)

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacing.rowPaddingX
                        spacing: Theme.spacing.gap

                        DialogButton {
                            id: cancelBtn
                            label: "Cancel"
                            onActivated: root.tsOpen = false
                        }

                        DialogButton {
                            id: okBtn
                            label: "OK"
                            primary: true
                            onActivated: {
                                root.beats = tsPanel.draftBeats
                                root.denominator = tsPanel.draftDenominator
                                root.tsOpen = false
                            }
                        }
                    }
                }
            }

    }

        // --- the keys sheet: ? opens it, esc, ? or the x closes it ---
        // The same card as the time signature editor, without actions: the
        // header carries the close, and a click outside is a close too.
        MouseArea {
            anchors.fill: parent
            visible: root.keysOpen
            onClicked: root.keysOpen = false
        }

        Rectangle {
            id: keysPanel
            anchors.centerIn: parent
            visible: root.keysOpen
            width: Theme.space(296)
            height: keysColumn.implicitHeight + 2 * Theme.spacing.rowPaddingX
            color: Theme.color.surface
            border.width: Theme.spacing.hairline
            border.color: Theme.color.muted
            radius: Theme.cornerRadius

            MouseArea { anchors.fill: parent }

            readonly property var bindings: [
                ["space", "play, stop"],
                ["↑ ↓", "tempo ±1"],
                ["shift ↑ ↓", "tempo ±5"],
                ["pgup pgdn", "tempo ±10"],
                ["t", "tap tempo"],
                ["1 2 4 8", "beat unit"],
                ["esc", "stop"],
                ["tab", "next control"],
                ["enter", "press the focused control"],
                ["ctrl q", "quit"],
                ["?", "this sheet"]
            ]

            Column {
                id: keysColumn
                width: parent.width
                anchors.top: parent.top
                anchors.topMargin: Theme.spacing.rowPaddingX
                spacing: 0

                Item {
                    width: parent.width
                    height: keysTitle.implicitHeight + Theme.spacing.gap

                    Text {
                        id: keysTitle
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacing.rowPaddingX
                        anchors.top: parent.top
                        text: "KEYS"
                        color: Theme.color.muted
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.caption
                    }

                    ChromeButton {
                        glyph: "✕"
                        glyphSize: Theme.font.bodySmall
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacing.gap
                        anchors.verticalCenter: keysTitle.verticalCenter
                        width: Theme.space(24)
                        height: Theme.space(20)
                        onActivated: root.keysOpen = false
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Theme.spacing.hairline
                        color: Theme.color.muted
                        opacity: 0.4
                    }
                }

                Column {
                    width: parent.width
                    topPadding: Theme.space(12)
                    spacing: Theme.space(6)

                    Repeater {
                        model: keysPanel.bindings

                        Item {
                            width: parent.width
                            height: keyLabel.implicitHeight

                            Text {
                                id: keyLabel
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacing.rowPaddingX
                                width: Theme.space(96)
                                text: modelData[0]
                                color: Theme.color.foreground
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.bodySmall
                            }

                            Text {
                                anchors.left: keyLabel.right
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacing.rowPaddingX
                                text: modelData[1]
                                color: Theme.color.muted
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.bodySmall
                                elide: Text.ElideRight
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
