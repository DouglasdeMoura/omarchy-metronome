//@ pragma AppId dev.douglasmoura.winkel
//@ pragma ShellId winkel
//@ pragma CacheDir $BASE/winkel

import Quickshell
import QtQuick
import "."

ShellRoot {
    id: shell

    function requestQuit() {
        if (backend.quitting) return
        main.flushSave()
        backend.quit()
    }

    Backend { id: backend }

    FloatingWindow {
        id: window
        // The app's name is a word like any other: a language names it.
        title: I18n.tr("app.name")
        // A golden window: 377 by 610, two neighbours on the Fibonacci run.
        implicitWidth: 377
        implicitHeight: 610
        color: Theme.color.background

        Rectangle {
            anchors.fill: parent
            color: Theme.color.background

            Main {
                id: main
                anchors.fill: parent
                backend: backend
                onCloseRequested: shell.requestQuit()
            }
        }

        // The close is a drain, not a cut: the window stays up until the
        // backend has answered quitready, so the last line out is the last
        // line the metronome meant to send.
        Connections {
            target: Quickshell
            function onLastWindowClosed() { shell.requestQuit() }
        }

        Connections {
            target: backend
            function onQuitReady() { Qt.quit() }
        }

        Component.onCompleted: main.forceActiveFocus()
    }
}
