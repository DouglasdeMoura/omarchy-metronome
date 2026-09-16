#!/usr/bin/env bash
# Retakes docs/screenshots: three views in each of the two themes the README
# shows. Offscreen, so it needs no session and lands the same pixels twice.
#
#   tools/screenshots.sh              # into docs/screenshots
#   tools/screenshots.sh /tmp/shots   # somewhere else, to compare first
#
# Each theme is shot under a HOME of its own, because Theme.qml reads the
# live theme out of $HOME/.local/state/omarchy/current: the theme's own
# colors.toml, and the shell.toml this machine's omarchy generated.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-$root/docs/screenshots}"
themes=(tokyo-night catppuccin-latte)

installed="$HOME/.local/share/omarchy/themes"
shell_toml="$HOME/.local/state/omarchy/current/theme/shell.toml"
for theme in "${themes[@]}"; do
    [ -f "$installed/$theme/colors.toml" ] || { echo "no omarchy theme '$theme' installed" >&2; exit 1; }
done
[ -f "$shell_toml" ] || { echo "no omarchy shell.toml at $shell_toml" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
sed "s#WINKEL_UI_DIR#file://$root/ui#" "$root/tools/screenshots.qml" > "$work/screenshots.qml"
mkdir -p "$out"

for theme in "${themes[@]}"; do
    home="$work/$theme"
    mkdir -p "$home/.local/state/omarchy/current/theme" "$home/runtime"
    cp "$installed/$theme/colors.toml" "$home/.local/state/omarchy/current/theme/"
    cp "$shell_toml" "$home/.local/state/omarchy/current/theme/"
    printf '%s' "$theme" > "$home/.local/state/omarchy/current/theme.name"

    HOME="$home" XDG_RUNTIME_DIR="$home/runtime" QT_QPA_PLATFORM=offscreen \
        SHOT_DIR="$out" SHOT_THEME="$theme" \
        timeout 60 qs -p "$work/screenshots.qml" >/dev/null 2>&1

    for view in main time-signature subdivision; do
        [ -f "$out/$theme-$view.png" ] || { echo "$theme-$view.png was not taken" >&2; exit 1; }
        echo "$out/$theme-$view.png"
    done
done
