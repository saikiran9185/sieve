#!/bin/bash
# Builds Sieve.app — a release binary wrapped in a signed bundle.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
NAME="Sieve"
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
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
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

# Hardened runtime: library validation on, code injection and unsigned-memory execution off.
codesign --force --deep --options=runtime   --entitlements "$ROOT/Sieve.entitlements"   --sign - --identifier "com.saikiran.$NAME" "$APP" 2>/dev/null

rm -f "$ROOT/Sieve.entitlements"

codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "^(Identifier|Signature|CodeDirectory)" | sed 's/^/  /'
echo "✓ Built $APP"
