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
Sieve — how to open it the first time


macOS WILL REFUSE TO OPEN THIS APP THE FIRST TIME. Here is why, and what to do.

You will see a box saying:

    "Sieve" Not Opened
    Apple could not verify "Sieve" is free of malware that may harm
    your Mac or compromise your privacy.
                    [ Move to Trash ]  [ Done ]

That is NOT a malware finding. Nothing was scanned and nothing was found. It is
what macOS says about any app that has not been through Apple's paid notarisation
service. Sieve is signed, and every download is published with a checksum you can
check, but notarisation costs $99 a year and this app is free.


=========================================================================
NO TERMINAL NEEDED — do this once and never again
=========================================================================

  1. Drag Sieve into the Applications folder next to this file.

  2. Open Sieve. The box above appears. Click "Done".
     Do NOT click "Move to Trash".

  3. Open System Settings  (Apple menu, top-left of your screen).

  4. Click "Privacy & Security" in the sidebar.

  5. Scroll down to the "Security" section near the bottom.
     You will see a line saying Sieve was blocked, with a button
     next to it: "Open Anyway".  Click it.

  6. Confirm with your fingerprint or password, then click "Open Anyway"
     once more if asked.

Sieve opens, and every launch after this one is normal. You only do this once.


=========================================================================
IF YOU ARE COMFORTABLE WITH TERMINAL — one line instead of steps 2 to 6
=========================================================================

    xattr -dr com.apple.quarantine /Applications/Sieve.app

That removes the "downloaded from the internet" mark. It changes nothing about
the app. Or skip this disk image entirely and install with:

    curl -fsSL https://raw.githubusercontent.com/saikiran9185/sieve/main/install.sh | bash

    brew install --cask saikiran9185/tap/sieve      (if you have Homebrew)


=========================================================================
WHAT SIEVE KEEPS
=========================================================================

Everything lives in a folder at  Documents > Sieve  on your own Mac.
No account, no sign-in, no telemetry, nothing sent anywhere. Delete that
folder and nothing of yours remains.

There is no Windows version. Sieve's PDF reader is built on Apple frameworks
that only exist on macOS; there is no way to run it on Windows.

Questions, problems, ideas:  https://github.com/saikiran9185/sieve
NOTE

echo "→ Building disk image…"
rm -f "$DMG"
hdiutil create -volname "$NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO \
  -fs HFS+ "$DMG" >/dev/null

rm -rf "${STAGE}"

# Sign the image with the same identity the app got, so the two agree.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"')
[ -z "$IDENTITY" ] && IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Apple Development:[^"]*"' | head -1 | tr -d '"')
codesign --force --sign "${IDENTITY:--}" "$DMG" 2>/dev/null || codesign --force --sign - "$DMG" 2>/dev/null || true

# Notarise when credentials are stored. Only a Developer ID signature can be notarised;
# see NOTARISING.md for how to get one and store the profile.
if [ -n "${SIEVE_NOTARY_PROFILE:-}" ]; then
  echo "→ Notarising (a few minutes)..."
  if xcrun notarytool submit "$DMG" --keychain-profile "$SIEVE_NOTARY_PROFILE" --wait; then
    xcrun stapler staple "$DMG" && echo "  ticket stapled — this image opens with no dialog anywhere"
  else
    echo "  notarisation failed; the image is still usable but will show the Gatekeeper dialog"
  fi
fi

echo "✓ Built $DMG  ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG" | awk '{print "  SHA-256: "$1}'
