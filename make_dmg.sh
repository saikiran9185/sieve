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
cat > "$STAGE/READ ME FIRST.txt" <<'NOTE'
Sieve

1. Drag Sieve into the Applications folder beside it.

2. The app is signed, but not notarised by Apple — notarisation requires a paid
   Apple Developer account. macOS will therefore refuse to open it the first time
   and may say the app is damaged. It is not. To clear the download quarantine
   flag, open Terminal and run:

       xattr -dr com.apple.quarantine /Applications/Sieve.app

   Then open Sieve normally.

   If you would rather not run that command, build it yourself instead — it takes
   about thirty seconds and has no dependencies:

       git clone https://github.com/saikiran9185/sieve.git
       cd sieve && ./build_app.sh

3. Everything Sieve stores lives in ~/Documents/Sieve. There is no account and no
   telemetry. Delete that folder and nothing remains.

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
