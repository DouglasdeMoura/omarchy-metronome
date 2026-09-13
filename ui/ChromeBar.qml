import QtQuick

// The thin strip at the top of the window: the close button alone, with one
// hairline under it, like every Omarchy card.
Rectangle {
    id: root

    signal closed()

    // The keyboard focus ring cycles through here too.
    readonly property alias closeItem: close

    readonly property int height_: Theme.golden(3)

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

    ChromeButton {
        id: close
        glyph: "✕"
        glyphSize: Theme.font.bodySmall
        anchors.right: parent.right
        anchors.rightMargin: Theme.golden(0)
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.golden(2)
        height: Theme.golden(2)
        onActivated: root.closed()
    }
}
