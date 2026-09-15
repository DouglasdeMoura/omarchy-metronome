# Releasing

A release is a version tag. CI builds the binaries and publishes the release;
the AUR packages are then updated by hand.

## 1. Bump the version

The version lives in five places, and they move together:

- `version` in `Cargo.toml`, then run `cargo build` so `Cargo.lock` follows.
- A new `<release version="…" date="…"/>` at the top of `<releases>` in
  `packaging/dev.douglasmoura.winkel.metainfo.xml`.
- A dated section in `CHANGELOG.md`.
- `pkgver` in `packaging/aur/winkel/PKGBUILD` and
  `packaging/aur/winkel-bin/PKGBUILD`, with `pkgrel=1`.

## 2. Check

```sh
make test
appstreamcli validate --no-net packaging/dev.douglasmoura.winkel.metainfo.xml
desktop-file-validate packaging/dev.douglasmoura.winkel.desktop
```

## 3. Tag

```sh
git commit -am "release: vX.Y.Z"
git tag vX.Y.Z
git push origin main vX.Y.Z
```

The `Release` workflow builds `winkel-X.Y.Z-x86_64-linux.tar.gz`
and `…-aarch64-linux.tar.gz` with their `.sha256` files and publishes them as
the GitHub release, with notes generated from the commits.

## 4. Update the AUR

Do this once the release exists, since the source and `-bin` packages
download from it. For `winkel` and `winkel-bin`:

```sh
cd packaging/aur/winkel
updpkgsums                          # replaces SKIP with the real checksums
makepkg --printsrcinfo > .SRCINFO
makepkg -si                         # build, test and install it locally
```

Then publish the directory's `PKGBUILD` and `.SRCINFO` to the AUR, which
needs an AUR account with your SSH key:

```sh
git clone ssh://aur@aur.archlinux.org/winkel.git /tmp/aur-winkel
cp PKGBUILD .SRCINFO /tmp/aur-winkel/
cd /tmp/aur-winkel
git add PKGBUILD .SRCINFO
git commit -m "Update to X.Y.Z"
git push
```

`winkel-git` builds whatever is on `main`, so it is published once
and only updated when its PKGBUILD changes.

Commit the updated checksums and `.SRCINFO` files back to this repository.

## 5. The Omarchy package repository

Omarchy users can already install from the AUR with
`omarchy pkg aur add winkel`. Shipping in Omarchy's own
repository, so `omarchy pkg add winkel` works with no AUR helper,
is up to Omarchy's maintainers.

`packaging/omarchy/winkel/` holds the two files a submission to
[omacom/omarchy-pkgs](https://github.com/omacom/omarchy-pkgs) needs:

- `PKGBUILD`, the source build, with Omarchy's dependency list style.
- `.omarchy/package.json`, which watches this repository's `v*` tags, so
  Omarchy's pipeline picks up each release after a 24-hour quarantine.

To submit, once a release exists:

```sh
gh repo fork omacom/omarchy-pkgs --clone
cd omarchy-pkgs
git switch -c add-winkel
cp -r ../winkel/packaging/omarchy/winkel pkgbuilds/
(cd pkgbuilds/winkel && updpkgsums)
git add pkgbuilds/winkel
git commit -m "Add winkel"
gh pr create --repo omacom/omarchy-pkgs --title "Add winkel"
```

Describe the app, link the source and its MIT licence, and say you are its
author and maintainer, as other package requests there do. After a release,
Omarchy's watch updates the version and checksums itself; the copy here only
matters for the first submission.
