import QtQuick

// A dialog action in Flea's shape: a hairline frame carrying live text, no
// fill. Only the frame takes muted, the role the shell gives borders and
// inactive controls; the primary action's frame and ink are the accent.
Item {
    id: root

    property string label: ""
    property bool primary: false

    signal activated()

    readonly property color frame: root.primary ? Theme.color.accent : Theme.color.muted
    readonly property color ink: root.primary ? Theme.color.accent : Theme.color.foreground

    implicitWidth: Math.max(Theme.hitMin, text.implicitWidth + 2 * Theme.spacing.gap + 2 * Theme.spacing.hairline)
    implicitHeight: Math.max(Theme.hitMin, text.implicitHeight + Theme.spacing.gap + 2 * Theme.spacing.hairline)
    scale: tap.pressed && !Theme.reducedMotion ? 0.96 : 1

    Behavior on scale {
        enabled: !Theme.reducedMotion
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: Theme.spacing.hairline
        border.color: root.frame
    }

    Text {
        id: text
        anchors.centerIn: parent
        text: root.label
        color: root.ink
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.activated()
    }
}
