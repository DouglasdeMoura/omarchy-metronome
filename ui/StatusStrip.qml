import QtQuick

// The thin strip at the bottom: the running count on the right, and — only
// when something is wrong — the error on the left, in urgent ink.
Rectangle {
    id: root

    property int totalBeats: 0
    property string error: ""

    implicitWidth: 380
    implicitHeight: Theme.space(30)
    color: "transparent"

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Theme.color.lineSoft
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: Theme.space(12)
        anchors.verticalCenter: parent.verticalCenter
        visible: root.error.length > 0
        text: root.error
        color: Theme.color.urgent
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        elide: Text.ElideRight
        width: parent.width - Theme.space(24) - counter.implicitWidth - Theme.space(12)
    }

    Text {
        id: counter
        anchors.right: parent.right
        anchors.rightMargin: Theme.space(12)
        anchors.verticalCenter: parent.verticalCenter
        text: root.totalBeats > 0 ? root.totalBeats + (root.totalBeats === 1 ? " beat" : " beats") : ""
        color: Theme.color.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
    }
}
