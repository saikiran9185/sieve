#!/bin/bash
# Packages Sieve.app into a disk image with the usual drag-to-Applications layout.
# usage: ./make_dmg.sh [version]
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-1.0}"
NAME="Sieve"
APP="$ROOT/$NAME.app"
DMG="$ROOT/$NAME-$VERSION.dmg"
STAGE="$(mktemp -d)"

[ -d "$APP" ] || { echo "No $NAME.app — run ./build_app.sh first."; exit 1; }

echo "→ Staging…"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# A short note so someone who downloads the image knows why macOS will complain.
cat > "${STAGE}/READ ME FIRST.txt" <<'NOTE'
Sieve


IF YOU DRAG THE APP ACROSS, macOS WILL REFUSE TO OPEN IT.

You will get a dialog saying "Apple could not verify Sieve is free of malware",
offering only "Move to Trash" and "Done". That is not a real malware finding. It
is what macOS shows for any app that has not been notarised by Apple, and
notarisation requires a paid Apple Developer account.


THE EASY WAY — paste this into Terminal instead of dragging:

    curl -fsSL https://raw.githubusercontent.com/saikiran9185/sieve/main/install.sh | bash

It downloads the app, checks it against the checksum published with the release,
installs it, and clears the download flag that triggers the dialog. Or, if you
have Homebrew:

    brew install --cask saikiran9185/tap/sieve


IF YOU ALREADY DRAGGED IT AND GOT THE DIALOG:

Click "Done" — NOT "Move to Trash" — then paste this into Terminal:

    xattr -dr com.apple.quarantine /Applications/Sieve.app

Then open Sieve normally. That command removes the "downloaded from the internet"
flag; it does not change the app.


OR BUILD IT YOURSELF — about thirty seconds, no dependencies:

    git clone https://github.com/saikiran9185/sieve.git
    cd sieve && ./build_app.sh


WHAT SIEVE STORES

Everything lives in ~/Documents/Sieve. No account, no telemetry, nothing sent
anywhere. Delete that folder and nothing remains.

Source, issues and feedback: https://github.com/saikiran9185/sieve
NOTE

echo "→ Building disk image…"
rm -f "$DMG"
hdiutil create -volname "$NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO \
  -fs HFS+ "$DMG" >/dev/null

rm -rf "$STAGE"
codesign --force --sign - "$DMG" 2>/dev/null || true

echo "✓ Built $DMG  ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG" | awk '{print "  SHA-256: "$1}'
