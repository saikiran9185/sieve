#!/bin/bash
# Builds Sieve.app — a release binary wrapped in a signed bundle.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
NAME="Sieve"
# The version shown in Finder, About, and to Homebrew. Passed in, or read from the newest
# git tag, so a build never misreports which release it is.
VERSION="${1:-$(git -C "$(cd "$(dirname "$0")" && pwd)" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0}"
BUILD="$(git -C "$(cd "$(dirname "$0")" && pwd)" rev-list --count HEAD 2>/dev/null || echo 1)"
APP="$ROOT/$NAME.app"

echo "→ Compiling (release)…"
swift build -c release --package-path "$ROOT"

BIN="$(swift build -c release --package-path "$ROOT" --show-bin-path)/$NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
[ -f "$ROOT/Sieve.icns" ] && cp "$ROOT/Sieve.icns" "$APP/Contents/Resources/$NAME.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>com.saikiran.$NAME</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIconFile</key><string>$NAME</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Local-first literature review tool</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>PDF document</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSItemContentTypes</key><array><string>com.adobe.pdf</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

cat > "$ROOT/Sieve.entitlements" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- Sieve talks to academic databases; it never listens for incoming connections. -->
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.network.server</key><false/>
  <!-- The optional Claude assistant runs the `claude` CLI as a child process. -->
  <key>com.apple.security.inherit</key><false/>
</dict>
</plist>
ENT

# Pick the strongest signing identity available.
#
#   Developer ID Application  — the only one Apple will notarise, and the only one that
#                               satisfies Gatekeeper on someone else's Mac. Needs the paid
#                               Apple Developer Program.
#   Apple Development         — free with any Apple ID. Gatekeeper accepts it on machines
#                               that trust the certificate, which in practice means yours.
#                               An ad-hoc build is refused there even unquarantined.
#   ad-hoc                    — no identity at all. Always shows the "could not verify"
#                               dialog on a fresh download.
#
# Override with SIEVE_SIGN_IDENTITY, or force the lowest with SIEVE_ADHOC=1.
if [ "${SIEVE_ADHOC:-0}" = "1" ]; then
  IDENTITY="-"; IDENTITY_NAME="ad-hoc (forced)"
elif [ -n "${SIEVE_SIGN_IDENTITY:-}" ]; then
  IDENTITY="$SIEVE_SIGN_IDENTITY"; IDENTITY_NAME="$SIEVE_SIGN_IDENTITY"
else
  IDENTITY_NAME=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"')
  [ -z "$IDENTITY_NAME" ] && IDENTITY_NAME=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o '"Apple Development:[^"]*"' | head -1 | tr -d '"')
  if [ -n "$IDENTITY_NAME" ]; then IDENTITY="$IDENTITY_NAME"; else IDENTITY="-"; IDENTITY_NAME="ad-hoc"; fi
fi

# Hardened runtime: library validation on, code injection and unsigned-memory execution off.
codesign --force --deep --options=runtime \
  --entitlements "$ROOT/Sieve.entitlements" \
  --sign "$IDENTITY" --identifier "com.saikiran.$NAME" "$APP" 2>/dev/null \
  || codesign --force --deep --options=runtime \
       --entitlements "$ROOT/Sieve.entitlements" \
       --sign - --identifier "com.saikiran.$NAME" "$APP" 2>/dev/null

rm -f "$ROOT/Sieve.entitlements"

codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "^(Identifier|Signature|CodeDirectory)" | sed 's/^/  /'
echo "✓ Built $APP  (version $VERSION, build $BUILD)"
echo "  signed with: $IDENTITY_NAME"
if [ "$IDENTITY" = "-" ]; then
  echo "  note: an ad-hoc build shows the \"Apple could not verify\" dialog on any Mac it is"
  echo "        downloaded to, including this one. See NOTARISING.md."
fi
