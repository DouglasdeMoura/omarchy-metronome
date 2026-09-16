#!/usr/bin/env bash
# Points Winkel's release recipes at a version and fills in real checksums
# from that release: the winkel and winkel-bin AUR recipes and the Omarchy
# recipe. The release must already be published.
#
#   packaging/aur/set-version.sh 0.2.0
set -euo pipefail

version="${1:-}"
version="${version#v}"
if ! [[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "usage: $0 X.Y.Z" >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/../.." && pwd)"
for recipe in packaging/aur/winkel packaging/aur/winkel-bin packaging/omarchy/winkel; do
  dir="$root/$recipe"
  if [ "$(sed -n 's/^pkgver=//p' "$dir/PKGBUILD")" != "$version" ]; then
    sed -i "s/^pkgver=.*/pkgver=$version/; s/^pkgrel=.*/pkgrel=1/" "$dir/PKGBUILD"
  fi
  (cd "$dir" && updpkgsums >/dev/null 2>&1 && rm -f ./*.tar.gz)
  echo "$recipe: $version"
done

# The -git recipe works its version out at build time; the one recorded here
# is what the AUR shows, so it follows the release and the commit it was cut
# from.
gitrecipe="$root/packaging/aur/winkel-git"
if [ -d "$gitrecipe" ] && commit="$(git -C "$root" rev-parse --short=7 HEAD 2>/dev/null)"; then
  sed -i "s/^pkgver=.*/pkgver=$version.r0.g$commit/" "$gitrecipe/PKGBUILD"
  echo "packaging/aur/winkel-git: $version.r0.g$commit"
fi
