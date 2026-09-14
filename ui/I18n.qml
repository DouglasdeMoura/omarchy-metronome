pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Every word the window shows comes through here. Catalogues are JSON files
// in ui/i18n, one per locale, English the source every other one follows;
// see docs/i18n.md. Qt's own translator is not used: Quickshell installs
// none and the .qm toolchain is not a runtime dependency, while a JSON file
// is something any translator can edit and any test can read.
Singleton {
    id: root

    readonly property string dir: decodeURIComponent(Qt.resolvedUrl("i18n").toString().replace(/^file:\/\//, ""))

    // The locale in use, normalized to language or language_REGION. The
    // pseudo locales are for testing: "pseudo" accents and lengthens every
    // string so a hard-coded or truncated label stands out, "pseudo-rtl"
    // does the same in a right-to-left layout.
    property string locale: detect()
    readonly property bool pseudo: locale === "pseudo" || locale === "pseudo-rtl"
    readonly property string language: pseudo ? "en" : locale.split("_")[0]
    readonly property bool rtl: locale === "pseudo-rtl"
        || (!pseudo && Qt.locale(locale).textDirection === Qt.RightToLeft)

    // The merged catalogue: English, overlaid by the language, overlaid by
    // the region. A binding that calls tr() reads this, so it retranslates
    // when a catalogue loads or the locale changes.
    property var messages: ({})
    property var warned: ({})

    // PULSE_LANG wins, then the POSIX order: LANGUAGE's first entry when a
    // real locale is set, LC_ALL, LC_MESSAGES, LANG.
    function detect() {
        var forced = Quickshell.env("PULSE_LANG")
        if (forced) return normalize(forced)
        var set = Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || ""
        var priority = Quickshell.env("LANGUAGE")
        if (priority && normalize(set) !== "en") return normalize(priority.split(":")[0])
        return normalize(set)
    }

    // "pt_BR.UTF-8@euro" and "pt-br" are both pt_BR; C and POSIX are English.
    function normalize(name) {
        name = String(name || "").split(".")[0].split("@")[0].replace("-", "_")
        if (name === "pseudo" || name === "pseudo_rtl") return name.replace("_", "-")
        if (name === "" || name === "C" || name === "POSIX") return "en"
        var parts = name.split("_")
        return parts.length > 1 ? parts[0].toLowerCase() + "_" + parts[1].toUpperCase() : parts[0].toLowerCase()
    }

    // For tests and tools: switch the locale in place.
    function setLocale(name) {
        root.locale = normalize(name)
    }

    function has(key) {
        return root.messages[key] !== undefined
    }

    // A message by key. args fill {placeholders}; args.count picks a plural
    // form, "=N" before the language's category, and args.form picks a
    // named form such as "all". A missing key shows as itself, loudly, so a
    // gap in a catalogue is seen rather than blank.
    function tr(key, args) {
        var entry = root.messages[key]
        if (entry === undefined) {
            if (!root.warned[key]) {
                root.warned[key] = true
                console.warn("i18n: no message for " + key + " in " + root.locale)
            }
            return key
        }
        var text = typeof entry === "object" ? pick(entry, args || {}) : entry
        if (root.pseudo) text = pseudoize(text)
        return substitute(text, args || {})
    }

    // A key cap or shortcut: left to right in every language, so it sits in
    // a left-to-right isolate and "1 2 4 8" never turns around inside a
    // right-to-left sentence. The pseudo right-to-left mark stays out of it.
    function shortcut(key) {
        var text = tr(key).replace(/^\u200f/, "")
        return String.fromCharCode(0x2066) + text + String.fromCharCode(0x2069)
    }

    function pick(entry, args) {
        if (args.form !== undefined && entry[args.form] !== undefined) return entry[args.form]
        if (args.count !== undefined) {
            var exact = entry["=" + args.count]
            if (exact !== undefined) return exact
            var category = entry[pluralCategory(args.count)]
            if (category !== undefined) return category
        }
        return entry.other !== undefined ? entry.other : ""
    }

    function substitute(text, args) {
        return text.replace(/\{(\w+)\}/g, function (whole, name) {
            return args[name] !== undefined ? String(args[name]) : whole
        })
    }

    // CLDR's plural categories for whole numbers, by language. Pulse only
    // ever counts whole things; a language not listed takes one and other.
    function pluralCategory(n) {
        var mod10 = n % 10
        var mod100 = n % 100
        switch (root.language) {
        case "ja": case "zh": case "ko": case "th": case "vi": case "id": case "ms": case "lo": case "my": case "km":
            return "other"
        case "fr": case "hy": case "kab":
            return n === 0 || n === 1 ? "one" : "other"
        case "pt":
            if (root.locale === "pt_PT") return n === 1 ? "one" : "other"
            return n === 0 || n === 1 ? "one" : "other"
        case "ru": case "uk": case "be":
            if (mod10 === 1 && mod100 !== 11) return "one"
            if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return "few"
            return "many"
        case "hr": case "sr": case "bs":
            if (mod10 === 1 && mod100 !== 11) return "one"
            if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return "few"
            return "other"
        case "pl":
            if (n === 1) return "one"
            if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return "few"
            return "many"
        case "cs": case "sk":
            return n === 1 ? "one" : n >= 2 && n <= 4 ? "few" : "other"
        case "sl":
            return mod100 === 1 ? "one" : mod100 === 2 ? "two" : mod100 === 3 || mod100 === 4 ? "few" : "other"
        case "lt":
            if (mod10 === 1 && (mod100 < 11 || mod100 > 19)) return "one"
            if (mod10 >= 2 && (mod100 < 11 || mod100 > 19)) return "few"
            return "other"
        case "lv":
            if (mod10 === 0 || (mod100 >= 11 && mod100 <= 19)) return "zero"
            return mod10 === 1 && mod100 !== 11 ? "one" : "other"
        case "ro":
            if (n === 1) return "one"
            return n === 0 || (mod100 >= 2 && mod100 <= 19) ? "few" : "other"
        case "ar":
            if (n === 0) return "zero"
            if (n === 1) return "one"
            if (n === 2) return "two"
            if (mod100 >= 3 && mod100 <= 10) return "few"
            if (mod100 >= 11) return "many"
            return "other"
        case "he":
            return n === 1 ? "one" : n === 2 ? "two" : "other"
        case "ga":
            return n === 1 ? "one" : n === 2 ? "two" : n >= 3 && n <= 6 ? "few" : n >= 7 && n <= 10 ? "many" : "other"
        case "cy":
            return n === 0 ? "zero" : n === 1 ? "one" : n === 2 ? "two" : n === 3 ? "few" : n === 6 ? "many" : "other"
        default:
            return n === 1 ? "one" : "other"
        }
    }

    // Accents and lengthens the message's own text, never its placeholders,
    // and brackets it so a clipped end is visible.
    function pseudoize(text) {
        var map = { a: "á", e: "é", i: "î", o: "ö", u: "ü", c: "ç", n: "ñ", s: "š", y: "ý",
                    A: "Å", E: "É", I: "Î", O: "Ö", U: "Û", C: "Ç", N: "Ñ", S: "Š", Y: "Ý" }
        var out = ""
        var depth = 0
        for (var i = 0; i < text.length; i++) {
            var ch = text.charAt(i)
            if (ch === "{") depth++
            out += depth > 0 ? ch : (map[ch] || ch)
            if (ch === "}" && depth > 0) depth--
        }
        var pad = new Array(Math.ceil(text.length * 0.3) + 1).join("·")
        return (root.locale === "pseudo-rtl" ? "‏" : "") + "⟦" + out + pad + "⟧"
    }

    // The candidate files, most specific first; empty paths load nothing.
    readonly property string regionFile: !pseudo && locale.indexOf("_") > 0 ? dir + "/" + locale + ".json" : ""
    readonly property string languageFile: !pseudo && language !== "en" ? dir + "/" + language + ".json" : ""

    function parse(view) {
        try {
            var body = view.text()
            return body ? JSON.parse(body) : {}
        } catch (e) {
            console.warn("i18n: " + view.path + " is not valid JSON (" + e + ")")
            return {}
        }
    }

    function rebuild() {
        var merged = {}
        var layers = [parse(baseView), parse(languageView), parse(regionView)]
        for (var l = 0; l < layers.length; l++)
            for (var key in layers[l]) merged[key] = layers[l][key]
        root.messages = merged
    }

    FileView {
        id: baseView
        path: root.dir + "/en.json"
        blockLoading: true
        printErrors: false
        onLoaded: root.rebuild()
        Component.onCompleted: root.rebuild()
    }

    FileView {
        id: languageView
        path: root.languageFile
        blockLoading: true
        printErrors: false
        onLoaded: root.rebuild()
        onLoadFailed: root.rebuild()
        onPathChanged: if (path === "") root.rebuild()
    }

    FileView {
        id: regionView
        path: root.regionFile
        blockLoading: true
        printErrors: false
        onLoaded: root.rebuild()
        onLoadFailed: root.rebuild()
        onPathChanged: if (path === "") root.rebuild()
    }
}
