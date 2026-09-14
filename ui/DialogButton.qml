import QtQuick

// A dialog action in Flea's shape: a hairline frame carrying live text, no
// fill. Only the frame takes muted, the role the shell gives borders and
// inactive controls; the primary action's frame and ink are the accent.
Item {
    id: root

    property string label: ""
    // What a screen reader says; a button that carries a figure or a glyph
    // instead of words names itself here.
    property string accessibleName: label
    property bool primary: false
    // The main view draws the same button larger and heavier; a dialog's
    // action keeps the defaults.
    property real horizontalPadding: Theme.spacing.gap
    property real verticalPadding: Theme.spacing.gap / 2
    property int pixelSize: Theme.font.body
    property int weight: Font.Normal
    // A quiet variant: a soft fill in place of the frame, for a control
    // that should sit back from the ones it serves.
    property bool framed: true
    property color fillColor: "transparent"
    // A button may carry a drawn figure instead of a label: children land
    // centred, and the label stays empty.
    default property alias content: slot.data

    signal activated()

    readonly property color frame: root.primary ? Theme.color.accent : Theme.color.muted
    readonly property color ink: root.primary ? Theme.color.accent : Theme.color.foreground

    implicitWidth: Math.max(Theme.hitMin, text.implicitWidth + 2 * horizontalPadding + 2 * Theme.spacing.hairline)
    implicitHeight: Math.max(Theme.hitMin, text.implicitHeight + 2 * verticalPadding + 2 * Theme.spacing.hairline)
    scale: tap.pressed && !Theme.reducedMotion ? 0.96 : 1

    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.onPressAction: root.activated()

    Behavior on scale {
        enabled: !Theme.reducedMotion
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    Rectangle {
        anchors.fill: parent
        color: root.fillColor
        border.width: root.framed ? Theme.spacing.hairline : 0
        border.color: root.frame
    }

    Item {
        id: slot
        anchors.centerIn: parent
        width: childrenRect.width
        height: childrenRect.height
    }

    Text {
        id: text
        anchors.centerIn: parent
        visible: root.label.length > 0
        text: root.label
        color: root.ink
        font.family: Theme.font.family
        font.pixelSize: root.pixelSize
        font.weight: root.weight
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.activated()
    }
}
