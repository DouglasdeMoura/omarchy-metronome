pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Pulse reads the Omarchy theme the same way Flea does: colors.toml and
// shell.toml are loaded before the first paint, and the one file a theme
// switch rewrites in place — theme.name — carries the watch, because
// omarchy-theme-set rm -rf's and mv's the theme directory and an inotify
// watch on a file inside it would die with the old inode.
Singleton {
    id: root

    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/current"

    // True only once colors.toml parsed to a palette, so a failure is visible
    // rather than a fallback silently standing in for a theme.
    property bool ready: false

    // The theme's own name, title-cased: "dracula" becomes "Dracula".
    property string themeName: ""

    // The only literal colours in the UI: the fallback palette, which holds
    // the window until colors.toml answers. They read as Dracula because that
    // palette is the shape every Omarchy theme follows.
    readonly property var fallback: ({
        background: "#282A36",
        foreground: "#F8F8F2",
        accent: "#BD93F9",
        muted: "#6272A4",
        surface: "#21222C",
        deep: "#21222C",
        urgent: "#FF5555",
        success: "#50FA7B"
    })

    readonly property QtObject color: QtObject {
        property color background: root.fallback.background
        property color foreground: root.fallback.foreground
        property color accent: root.fallback.accent
        property color muted: root.fallback.muted
        property color surface: root.fallback.surface
        property color deep: root.fallback.deep
        property color urgent: root.fallback.urgent
        property color success: root.fallback.success
        // Control chrome lines, the way the shell's [controls] tokens read:
        // foreground ink at the alphas the shell itself uses.
        readonly property color line: Qt.alpha(root.color.foreground, 0.25)
        readonly property color lineSoft: Qt.alpha(root.color.foreground, 0.12)
    }

    readonly property QtObject font: QtObject {
        property string family: Quickshell.env("PULSE_FONT") || "JetBrainsMono Nerd Font"
        // Omarchy's rem root, from shell.toml [font] base-size; every token
        // below is the shell's own ratio of it.
        property int baseSize: 12
        readonly property int caption: Math.round(baseSize * 10 / 12)
        readonly property int bodySmall: Math.round(baseSize * 11 / 12)
        readonly property int body: baseSize
        readonly property int subtitle: Math.round(baseSize * 13 / 12)
        readonly property int title: Math.round(baseSize * 14 / 12)
        readonly property int heading: Math.round(baseSize * 16 / 12)
        readonly property int display: Math.round(baseSize * 24 / 12)
        // The hero numeral is the one place Pulse outgrows the shell ladder.
        readonly property int hero: Math.round(baseSize * 64 / 12)
    }

    // shell.toml [spacing] scale, the same multiplier the bar applies.
    property real spacingScale: 1.0

    function space(px) {
        return Math.round(px * spacingScale)
    }

    // Flea's dialog frame tokens at the shell's defaults, so a card here
    // lines up with a card there: a hairline, a row's side padding, a gap.
    // The smallest a dialog action gets, Flea's own floor.
    readonly property int hitMin: 24

    readonly property QtObject spacing: QtObject {
        readonly property int hairline: root.space(1)
        readonly property int rowPaddingX: root.space(12)
        readonly property int gap: root.space(8)
    }

    // The compositor's corner radius, so a window follows the theme the way
    // every other surface on the desktop does; 0 until hyprctl has answered.
    property int cornerRadius: 0
    // Flea's rule: the compositor owns motion, so a desktop with animations
    // off gets a metronome that only ever cuts, never eases.
    property bool reducedMotion: false

    function applyColors(body) {
        var found = parseToml(body, "")
        function pick(keys, fb) {
            for (var i = 0; i < keys.length; i++)
                if (found[keys[i]] !== undefined) return found[keys[i]]
            return fb
        }
        root.color.background = pick(["background"], fallback.background)
        root.color.foreground = pick(["foreground"], fallback.foreground)
        root.color.accent = pick(["accent", "purple"], fallback.accent)
        root.color.muted = pick(["muted", "comment"], fallback.muted)
        // The dialog card's ground, the keys Flea's Open with card reads in
        // Flea's own order: the dark ground first, the window's, then selection.
        root.color.surface = pick(["dark_background", "background", "selection"], fallback.surface)
        root.color.deep = pick(["dark_background", "color0"], fallback.deep)
        root.color.urgent = pick(["red"], fallback.urgent)
        root.color.success = pick(["green"], fallback.success)
        // A body that parsed to nothing left every role on its fallback.
        root.ready = Object.keys(found).length > 0
    }

    function applyShell(body) {
        // Sections are flattened to "font.base-size" style keys.
        var doc = parseToml(body, "section")
        if (doc["font.base-size"] !== undefined) {
            var base = parseInt(doc["font.base-size"])
            if (base > 0) root.font.baseSize = base
        }
        var scale = 1.0
        if (doc["spacing.scale"] !== undefined) {
            var s = parseFloat(doc["spacing.scale"])
            if (s > 0) scale = s
        }
        // scale-with-font is the shell's own rule: spacing grows with the
        // base size, measured from the 12 it defaults to.
        var withFont = doc["spacing.scale-with-font"] !== "false"
        root.spacingScale = scale * (withFont ? root.font.baseSize / 12 : 1)
    }

    // The smallest TOML reader the two files call for: key = value lines,
    // [sections], quoted strings, numbers, booleans; comments per line.
    function parseToml(body, sectionMode) {
        var out = {}
        if (!body) return out
        var section = ""
        var lines = body.split("\n")
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            var hash = indexOfComment(line)
            if (hash >= 0) line = line.substring(0, hash)
            line = line.trim()
            if (line.length === 0) continue
            if (line.charAt(0) === "[") {
                section = line.replace(/^\[+/, "").replace(/\]+$/, "").trim() + "."
                continue
            }
            var eq = line.indexOf("=")
            if (eq < 0) continue
            var key = line.substring(0, eq).trim()
            var value = line.substring(eq + 1).trim()
            if (sectionMode !== "section") section = ""
            out[section + key] = unquote(value)
        }
        return out
    }

    // A '#' only starts a comment outside quotes.
    function indexOfComment(line) {
        var quoted = false
        for (var i = 0; i < line.length; i++) {
            var c = line.charAt(i)
            if (c === '"' && line.charAt(i - 1) !== "\\") quoted = !quoted
            else if (c === "#" && !quoted) return i
        }
        return -1
    }

    function unquote(value) {
        if (value.length >= 2 && value.charAt(0) === '"' && value.charAt(value.length - 1) === '"')
            return value.substring(1, value.length - 1)
        return value
    }

    function titleCase(slug) {
        return slug.replace(/(^|-)([a-z])/g, function (m, p1, p2) { return p1 + p2.toUpperCase() })
                   .replace(/-/g, " ")
    }

    FileView {
        id: colorsFile
        path: root.stateDir + "/theme/colors.toml"
        blockLoading: true
        printErrors: false
        onLoaded: root.applyColors(text())
        onLoadFailed: root.ready = false
        Component.onCompleted: root.applyColors(colorsFile.text())
    }

    // The type ladder and the spacing scale ride the theme too, so a theme
    // that ships a bigger base size gets a bigger metronome.
    FileView {
        id: shellFile
        path: root.stateDir + "/theme/shell.toml"
        blockLoading: true
        printErrors: false
        onLoaded: root.applyShell(text())
        onLoadFailed: root.applyShell("")
        Component.onCompleted: root.applyShell(shellFile.text())
    }

    FileView {
        id: themeNameFile
        path: root.stateDir + "/theme.name"
        blockLoading: true
        watchChanges: true
        printErrors: false
        // The name is taken from onLoaded, not from the watch handler: a
        // reload is not done until onLoaded says so, and a name read inline
        // lags one theme behind.
        onLoaded: root.themeName = root.titleCase(text().trim())
        onFileChanged: {
            reload()
            colorsFile.reload()
            shellFile.reload()
        }
        Component.onCompleted: reload()
    }

    // Read once, not watched: a theme change restarts nothing here and the
    // compositor's rounding is not a value Pulse could disagree with twice.
    Process {
        id: roundingQuery
        running: true
        command: ["hyprctl", "-j", "getoption", "decoration:rounding"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var doc = JSON.parse(text)
                    var v = doc.int !== undefined ? doc.int : parseInt(doc.str)
                    if (!isNaN(v) && v >= 0) root.cornerRadius = v
                } catch (e) {}
            }
        }
    }

    Process {
        id: motionQuery
        running: true
        command: ["hyprctl", "-j", "getoption", "animations:enabled"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var doc = JSON.parse(text)
                    if (doc.bool !== undefined) root.reducedMotion = !doc.bool
                } catch (e) {}
            }
        }
    }
}
