#!/bin/bash
# Baut Kost.app in diesem Ordner. Aufruf: ./build.sh  (mit --verteilen zusätzlich Kost.dmg)
set -euo pipefail
cd "$(dirname "$0")"

# Universell (Apple Silicon und Intel), damit die App auf jedem Mac ab macOS 14 läuft
swift build -c release --arch arm64 --arch x86_64

APP="Kost.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/de.lproj"
cp .build/apple/Products/Release/Kost "$APP/Contents/MacOS/Kost"

# Symbol nur neu zeichnen, wenn es fehlt oder das Zeichenskript jünger ist
if [ ! -f Werkzeug/Kost.icns ] || [ Werkzeug/symbol.swift -nt Werkzeug/Kost.icns ]; then
    SATZ="$(mktemp -d)/Kost.iconset"
    mkdir -p "$SATZ"
    swift Werkzeug/symbol.swift "$SATZ/quelle.png"
    for GROESSE in 16 32 128 256 512; do
        sips -z "$GROESSE" "$GROESSE" "$SATZ/quelle.png" --out "$SATZ/icon_${GROESSE}x${GROESSE}.png" >/dev/null
        sips -z "$((GROESSE * 2))" "$((GROESSE * 2))" "$SATZ/quelle.png" --out "$SATZ/icon_${GROESSE}x${GROESSE}@2x.png" >/dev/null
    done
    rm "$SATZ/quelle.png"
    iconutil -c icns "$SATZ" -o Werkzeug/Kost.icns
fi
cp Werkzeug/Kost.icns "$APP/Contents/Resources/Kost.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Kost</string>
    <key>CFBundleDisplayName</key><string>Kost</string>
    <key>CFBundleIdentifier</key><string>io.github.businessbaum.kost</string>
    <key>CFBundleExecutable</key><string>Kost</string>
    <key>CFBundleIconFile</key><string>Kost</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleDevelopmentRegion</key><string>de</string>
    <key>CFBundleLocalizations</key><array><string>de</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.healthcare-fitness</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Fertig: $(pwd)/$APP"

# Mit --verteilen entsteht zusätzlich Kost.dmg zum Weitergeben
if [ "${1:-}" = "--verteilen" ]; then
    INHALT="$(mktemp -d)/Kost"
    mkdir -p "$INHALT"
    cp -R "$APP" "$INHALT/"
    ln -s /Applications "$INHALT/Programme"
    cp Werkzeug/Zuerst-lesen.txt "$INHALT/Zuerst lesen.txt"
    rm -f Kost.dmg
    hdiutil create -volname "Kost" -srcfolder "$INHALT" -ov -format UDZO Kost.dmg >/dev/null
    echo "Zum Weitergeben: $(pwd)/Kost.dmg"
fi
