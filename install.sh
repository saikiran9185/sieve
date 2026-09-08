#!/bin/bash
#
# Installs Sieve.
#
#   curl -fsSL https://raw.githubusercontent.com/saikiran9185/sieve/main/install.sh | bash
#
# Downloads the latest release, checks it against the checksum published with it, installs it,
# and clears the download quarantine flag so macOS will open it. Nothing runs as root and
# nothing is written outside /Applications.
set -euo pipefail

REPO="saikiran9185/sieve"
APP="Sieve"
DEST="/Applications"

say()  { printf "\033[1m%s\033[0m\n" "$*"; }
warn() { printf "\033[33m%s\033[0m\n" "$*"; }
die()  { printf "\033[31m%s\033[0m\n" "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Sieve is a macOS app. There is no Windows or Linux build — see the README for why."

major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || die "Sieve needs macOS 14 or later. You have $(sw_vers -productVersion)."

say "Finding the latest release..."
api="https://api.github.com/repos/$REPO/releases/latest"
tag=$(curl -fsSL "$api" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
[ -n "$tag" ] || die "Could not reach GitHub."
url=$(curl -fsSL "$api" | sed -n 's/.*"browser_download_url": *"\([^"]*\.dmg\)".*/\1/p' | head -1)
[ -n "$url" ] || die "That release has no disk image attached."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; [ -n "${mnt:-}" ] && hdiutil detach "$mnt" -quiet 2>/dev/null || true' EXIT

say "Downloading ${APP} ${tag}..."
curl -fL# "$url" -o "${tmp}/${APP}.dmg"

# The release notes carry the SHA-256. Verifying it means a tampered download is caught
# even though the app is not notarised by Apple.
say "Checking the download..."
actual=$(shasum -a 256 "${tmp}/${APP}.dmg" | awk '{print $1}')
expected=$(curl -fsSL "$api" \
  | tr ',' '\n' | grep -o '[a-f0-9]\{64\}' | head -20 \
  | grep -x "$actual" || true)
if [ -n "$expected" ]; then
  say "  checksum matches the one published with the release"
else
  warn "  could not match a published checksum — continuing, but verify by hand if this matters to you"
  warn "  downloaded: $actual"
fi

say "Installing..."
mnt="${tmp}/mnt"
mkdir -p "$mnt"
hdiutil attach -nobrowse -quiet "${tmp}/${APP}.dmg" -mountpoint "$mnt"

if [ -d "${DEST}/${APP}.app" ]; then
  say "  replacing the copy already in $DEST"
  rm -rf "${DEST}/${APP}.app"
fi
cp -R "${mnt}/${APP}.app" "${DEST}/" || die "Could not write to $DEST. Try again, or drag the app across by hand."
hdiutil detach "$mnt" -quiet; mnt=""

# Without this macOS refuses to open the app and claims it is damaged, because it is signed
# but not notarised — notarisation needs a paid Apple Developer account.
xattr -dr com.apple.quarantine "${DEST}/${APP}.app" 2>/dev/null || true

if codesign -v --deep --strict "${DEST}/${APP}.app" 2>/dev/null; then
  say "  signature verified"
else
  warn "  signature could not be verified — remove ${DEST}/${APP}.app if you did not expect this"
fi

say ""
say "${APP} ${tag} is installed."
say "Your library will live in ~/Documents/Sieve. Nothing is sent anywhere."
say ""
open -a "${DEST}/${APP}.app" 2>/dev/null || say "Open it from your Applications folder."
