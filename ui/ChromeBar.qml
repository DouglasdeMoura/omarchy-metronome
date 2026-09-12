import QtQuick

// The thin strip at the top of the window: the mark, the name, the live theme
// name, and the close button. One hairline under it, like every Omarchy card.
Rectangle {
    id: root

    signal closed()

    // The keyboard focus ring cycles through here too.
    readonly property alias closeItem: close

    readonly property int height_: Theme.space(38)

    color: "transparent"

    implicitWidth: 380
    implicitHeight: height_

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.color.lineSoft
    }

    Item {
        id: mark
        width: Theme.space(20)
        height: Theme.space(20)
        anchors.left: parent.left
        anchors.leftMargin: Theme.space(12)
        anchors.verticalCenter: parent.verticalCenter

        // The pulse mark: one heartbeat, drawn, not typed, so it never falls
        // back to a tofu box on a font that lacks the glyph.
        Canvas {
            id: pulseMark
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = Theme.color.accent
                ctx.lineWidth = 2
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                var y = height / 2
                ctx.beginPath()
                ctx.moveTo(0, y)
                ctx.lineTo(width * 0.18, y)
                ctx.lineTo(width * 0.32, y - height * 0.28)
                ctx.lineTo(width * 0.48, y + height * 0.36)
                ctx.lineTo(width * 0.64, y - height * 0.4)
                ctx.lineTo(width * 0.76, y)
                ctx.lineTo(width, y)
                ctx.stroke()
            }
            // The theme can move the accent under a live window; the mark
            // repaints when it does.
            Connections {
                target: Theme.color
                function onAccentChanged() { pulseMark.requestPaint() }
            }
        }
    }

    Text {
        text: "Pulse"
        anchors.left: mark.right
        anchors.leftMargin: Theme.space(8)
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.color.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.title
        font.weight: Font.DemiBold
    }

    ChromeButton {
        id: close
        glyph: "✕"
        glyphSize: Theme.font.bodySmall
        anchors.right: parent.right
        anchors.rightMargin: Theme.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.space(28)
        height: root.height_ - Theme.space(8)
        onActivated: root.closed()
    }
}
