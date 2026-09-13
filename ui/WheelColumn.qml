import QtQuick

// One wheel of the time-signature picker: drag it, scroll it, or click a
// value; whatever rests in the middle band is the pick.
ListView {
    id: root

    // The values this wheel spins through, in display order.
    property var values: []
    // The value resting in the middle band.
    property int picked: values.length > 0 ? values[0] : 0

    readonly property int cell: Theme.space(30)
    readonly property int windowHeight: Theme.space(150)

    implicitWidth: Theme.space(64)
    implicitHeight: windowHeight
    clip: true
    model: values.length
    currentIndex: 0

    // Centre the highlight band and snap to it — the whole wheel trick. The
    // header and footer are the empty space that lets the first and last
    // value reach the middle. StrictlyEnforceRange is what makes a scroll
    // or a drag a pick: whatever the view settles on in the band becomes
    // the current item, no click needed.
    highlightRangeMode: ListView.StrictlyEnforceRange
    preferredHighlightBegin: (height - cell) / 2
    preferredHighlightEnd: preferredHighlightBegin + cell
    snapMode: ListView.SnapToItem

    header: Item { width: 1; height: (root.windowHeight - root.cell) / 2 }
    footer: Item { width: 1; height: (root.windowHeight - root.cell) / 2 }

    onCurrentIndexChanged: {
        if (values.length > 0 && currentIndex >= 0)
            picked = values[currentIndex]
    }

    // Spin the wheel so `value` rests in the middle. Deferred, because a
    // select can arrive before the view has its final height, and centering
    // needs the height.
    function select(value) {
        var i = values.indexOf(value)
        if (i < 0) return
        currentIndex = i
        Qt.callLater(function () { positionViewAtIndex(i, ListView.Center) })
    }

    onHeightChanged: positionViewAtIndex(currentIndex, ListView.Center)

    // The middle band: home of the pick.
    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        y: (root.height - root.cell) / 2
        height: root.cell

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Theme.color.lineSoft
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.color.lineSoft
        }
    }

    delegate: Item {
        id: entry
        width: root.width
        height: root.cell

        // Fade with distance from the middle band, so the pick reads first.
        opacity: 0.3 + 0.7 * (1 - Math.min(1, Math.abs(
            entry.y - root.contentY + entry.height / 2 - root.height / 2) / (root.height / 2)))

        Text {
            anchors.centerIn: parent
            text: root.values[index]
            color: index === root.currentIndex ? Theme.color.accent : Theme.color.foreground
            font.family: Theme.font.family
            font.pixelSize: index === root.currentIndex ? Theme.font.body : Theme.font.bodySmall
        }

        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.select(root.values[index]) }
    }

    Component.onCompleted: if (count > 0) positionViewAtIndex(0, ListView.Center)
}
