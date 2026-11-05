#!/bin/bash
# Packages the Swift sources in Sources/ into "Metal HUD Manager.app".
#
# Usage:
#   ./build-app.sh            -> builds into ./build/
#   ./build-app.sh --install  -> builds and copies the app to /Applications
#
# Environment variables:
#   VERSION=1.2.0    version written to Info.plist (default 1.0.0)
#   UNIVERSAL=1      build a universal binary (Apple Silicon + Intel)
#   BUNDLE_ID=...    override the bundle identifier

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Metal HUD Manager"
EXEC_NAME="MetalHUDManager"
BUNDLE_ID="${BUNDLE_ID:-io.github.ruggedx.MetalHUDManager}"
VERSION="${VERSION:-1.0.0}"
MIN_MACOS="13.0"

BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v swiftc >/dev/null || { echo "swiftc not found. Run: xcode-select --install"; exit 1; }
SOURCES=()
for f in Sources/*.swift Sources/*/*.swift; do [[ -f "$f" ]] && SOURCES+=("$f"); done
[[ ${#SOURCES[@]} -gt 0 ]] || { echo "No Swift sources found in Sources/."; exit 1; }

echo "==> Preparing bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling"
BIN="$APP/Contents/MacOS/$EXEC_NAME"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    swiftc -parse-as-library -O -target "arm64-apple-macos$MIN_MACOS"  "${SOURCES[@]}" -o "$TMP/$EXEC_NAME-arm64"
    swiftc -parse-as-library -O -target "x86_64-apple-macos$MIN_MACOS" "${SOURCES[@]}" -o "$TMP/$EXEC_NAME-x86_64"
    lipo -create "$TMP/$EXEC_NAME-arm64" "$TMP/$EXEC_NAME-x86_64" -output "$BIN"
else
    swiftc -parse-as-library -O "${SOURCES[@]}" -o "$BIN"
fi

echo "==> Generating icon"
cat > "$TMP/icon.swift" <<'SWIFT'
import AppKit
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(colors: [
    NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.16, alpha: 1),
    NSColor(calibratedRed: 0.20, green: 0.26, blue: 0.42, alpha: 1)
])!.draw(in: tile, angle: 90)
let config = NSImage.SymbolConfiguration(pointSize: 460, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.systemGreen]))
let symbol = (NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: nil)
           ?? NSImage(systemSymbolName: "speedometer", accessibilityDescription: nil))?
    .withSymbolConfiguration(config)
if let s = symbol {
    let r = NSRect(x: (size - s.size.width) / 2, y: (size - s.size.height) / 2,
                   width: s.size.width, height: s.size.height)
    s.draw(in: r)
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

ICON_LINE=""
if swift "$TMP/icon.swift" "$TMP/icon.png" 2>/dev/null; then
    ICONSET="$TMP/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        d=$((s * 2))
        sips -z $d $d "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    ICON_LINE="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
    echo "    (icon generation failed, continuing without an icon)"
fi

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$EXEC_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    $ICON_LINE
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications"
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    echo "Done: /Applications/$APP_NAME.app"
else
    echo "Done: $APP"
fi
