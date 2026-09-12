//@ pragma AppId com.douglasdemoura.pulse
//@ pragma ShellId pulse
//@ pragma CacheDir $BASE/pulse

import Quickshell
import QtQuick
import "."

ShellRoot {
    id: shell

    Backend { id: backend }

    FloatingWindow {
        id: window
        title: "Pulse"
        implicitWidth: 380
        implicitHeight: 600
        color: Theme.color.background

        Rectangle {
            anchors.fill: parent
            color: Theme.color.background

            Main {
                id: main
                anchors.fill: parent
                backend: backend
                onCloseRequested: window.close()
            }
        }

        // The close is a drain, not a cut: the window stays up until the
        // backend has answered quitready, so the last line out is the last
        // line the metronome meant to send.
        Connections {
            target: Quickshell
            function onLastWindowClosed() { backend.quit() }
        }

        Connections {
            target: backend
            function onQuitReady() { window.close() }
        }

        Component.onCompleted: main.forceActiveFocus()
    }
}
