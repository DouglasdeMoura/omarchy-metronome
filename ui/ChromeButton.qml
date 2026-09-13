import QtQuick

// Chrome buttons use muted ink, the rule Flea's own chrome follows.
Item {
    id: root

    property string glyph: ""
    property color restingColor: Theme.color.muted
    property real glyphSize: Theme.font.body + 2

    signal activated()

    implicitWidth: Math.max(Theme.space(28), glyphSize + Theme.space(12))
    implicitHeight: Theme.space(28)
    scale: tap.pressed && root.enabled && !Theme.reducedMotion ? 0.94 : 1

    Behavior on scale {
        enabled: !Theme.reducedMotion
        NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
    }

    Text {
        anchors.centerIn: parent
        text: root.glyph
        color: !root.enabled ? Theme.color.muted : root.restingColor
        font.family: Theme.font.family
        font.pixelSize: root.glyphSize
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton
        onTapped: root.activated()
    }
}
