#!/usr/bin/env bash
# Publishes Winkel's AUR packages from the recipes beside this script.
#
#   packaging/aur/publish.sh --dry-run            prepare all three, push nothing
#   packaging/aur/publish.sh                      publish winkel, winkel-bin, winkel-git
#   packaging/aur/publish.sh winkel winkel-bin    publish only these
#
# Each package's AUR repository is cloned into $AUR_WORKDIR (default
# ~/.cache/winkel-aur), refreshed .SRCINFO and PKGBUILD are copied in and
# committed, and master is pushed to aur.archlinux.org. The AUR creates a
# package the first time its repository is pushed. Needs an SSH key
# registered with your AUR account; see docs/releasing.md.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
dry=""
if [ "${1:-}" = "--dry-run" ]; then
  dry="--dry-run"
  shift
fi
[ $# -gt 0 ] || set -- winkel winkel-bin winkel-git
work="${AUR_WORKDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/winkel-aur}"
mkdir -p "$work"

for pkg in "$@"; do
  recipe="$here/$pkg"
  [ -f "$recipe/PKGBUILD" ] || { echo "$pkg: no recipe at $recipe" >&2; exit 1; }
  (cd "$recipe" && makepkg --printsrcinfo > .SRCINFO)

  repo="$work/$pkg"
  if [ ! -d "$repo/.git" ]; then
    git clone -q "ssh://aur@aur.archlinux.org/$pkg.git" "$repo" 2>/dev/null
  elif git -C "$repo" rev-parse -q --verify HEAD >/dev/null; then
    git -C "$repo" pull -q --ff-only
  fi
  git -C "$repo" checkout -q -B master

  cp "$recipe/PKGBUILD" "$recipe/.SRCINFO" "$repo/"
  git -C "$repo" add PKGBUILD .SRCINFO

  ver="$(sed -n 's/^\tpkgver = //p' "$recipe/.SRCINFO" | head -1)"
  rel="$(sed -n 's/^\tpkgrel = //p' "$recipe/.SRCINFO" | head -1)"
  if git -C "$repo" diff --cached --quiet; then
    echo "$pkg: $ver-$rel already committed"
  elif git -C "$repo" rev-parse -q --verify HEAD >/dev/null; then
    git -C "$repo" commit -q -m "Update to $ver-$rel"
    echo "$pkg: committed update to $ver-$rel"
  else
    git -C "$repo" commit -q -m "Initial upload: $pkg $ver-$rel"
    echo "$pkg: committed initial upload of $ver-$rel"
  fi

  git -C "$repo" push $dry -q origin master
  if [ -n "$dry" ]; then
    echo "$pkg: dry run, nothing pushed; the commit waits in $repo"
  else
    echo "$pkg: published, https://aur.archlinux.org/packages/$pkg"
  fi
done
