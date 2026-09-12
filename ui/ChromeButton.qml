import QtQuick

// Chrome buttons use muted ink; active and keyboard-focused use the accent,
// the rule Flea's own chrome follows.
Item {
    id: root

    property string glyph: ""
    property bool active: false
    property bool keyboardFocused: false
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

    Rectangle {
        anchors.centerIn: parent
        width: Math.max(Theme.space(24), parent.width)
        height: Math.max(Theme.space(24), parent.height)
        radius: 0
        visible: root.keyboardFocused
        color: "transparent"
        border.width: 1
        border.color: Theme.color.accent
    }

    Text {
        anchors.centerIn: parent
        text: root.glyph
        color: !root.enabled ? Theme.color.muted
                             : root.active || root.keyboardFocused ? Theme.color.accent
                                                                   : root.restingColor
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
