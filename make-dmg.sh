#!/bin/bash
# Sestaví instalační DMG pro distribuci: build/DockPeek-<verze>.dmg
#
# - univerzální binárka (Apple Silicon + Intel)
# - podpis s hardened runtime
# - s certifikátem "Developer ID Application" a NOTARY_PROFILE i notarizace,
#   takže stažená aplikace jde otevřít bez varování Gatekeeperu
#
# Použití:
#   ./make-dmg.sh
#   NOTARY_PROFILE=dockpeek ./make-dmg.sh          # s notarizací
#   CODESIGN_IDENTITY="Developer ID Application: …" ./make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DIST=build/dist
APP="$DIST/DockPeek.app"
DMG="build/DockPeek-$VERSION.dmg"

echo "==> Sestavuji univerzální binárku (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN=.build/apple/Products/Release/DockPeek

echo "==> Skládám DockPeek.app"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DockPeek"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/CreatorLogo.png Resources/CreatorLogo-dark.png "$APP/Contents/Resources/"

# Podpisový certifikát týmu TEAM_ID: Developer ID (distribuce) > Apple Development > ad-hoc
source ./signing.sh
DEVELOPER_ID=0
IDENTITY="${CODESIGN_IDENTITY:-$(find_identity "Developer ID Application")}"
if [ -n "$IDENTITY" ] && security find-identity -v -p codesigning | grep "$IDENTITY" | grep -q "Developer ID Application"; then
    DEVELOPER_ID=1
fi
[ -z "$IDENTITY" ] && IDENTITY=$(find_identity "Apple Development")
IDENTITY="${IDENTITY:--}"

SIGN_FLAGS=(--force --options runtime --entitlements Resources/DockPeek.entitlements --sign "$IDENTITY")
[ "$DEVELOPER_ID" = 1 ] && SIGN_FLAGS+=(--timestamp)

echo "==> Podepisuji aplikaci ($IDENTITY)"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo "==> Vytvářím DMG"
STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Aplikace"
# Ikona svazku
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"
SetFile -a C "$STAGE" 2>/dev/null || true

rm -f "$DMG"
hdiutil create -quiet -volname "DockPeek $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
if [ "$DEVELOPER_ID" = 1 ]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
else
    codesign --force --sign "$IDENTITY" "$DMG"
fi

if [ "$DEVELOPER_ID" = 1 ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizace (profil $NOTARY_PROFILE) – může trvat pár minut"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
    echo "Hotovo: $DMG (podepsáno Developer ID, notarizováno)"
elif [ "$DEVELOPER_ID" = 1 ]; then
    echo "Hotovo: $DMG (Developer ID, BEZ notarizace – nastavte NOTARY_PROFILE)"
else
    echo
    echo "Hotovo: $DMG"
    echo "POZOR: chybí certifikát 'Developer ID Application', DMG není notarizované."
    echo "Na jiném Macu ho macOS při prvním otevření zablokuje – viz README, sekce Instalace z DMG."
fi
