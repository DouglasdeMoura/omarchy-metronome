#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/pulse-ui-test.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
mkdir "$test_dir/runtime" "$test_dir/cache"
# The assertions are written in English: pin the locale whatever the host says.
PULSE_LANG=en QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic \
XDG_RUNTIME_DIR="$test_dir/runtime" XDG_CACHE_HOME="$test_dir/cache" \
timeout 15s qs -p test-ui.qml --no-color > "$test_dir/output" 2>&1
cat "$test_dir/output"
# QML exceptions do not necessarily change Quickshell's exit status.
rg -q 'PASS: frontend voices' "$test_dir/output"
