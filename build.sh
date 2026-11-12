#!/bin/bash
# Sestaví DockPeek.app do ./build a podepíše ho.
# Stabilní podpis (Apple Development) je důležitý: macOS váže oprávnění
# (Zpřístupnění, Nahrávání obrazovky) na podpis, s ad-hoc podpisem by se
# po každém buildu ztratila.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/DockPeek.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DockPeek "$APP/Contents/MacOS/DockPeek"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/CreatorLogo.png Resources/CreatorLogo-dark.png "$APP/Contents/Resources/"

source ./signing.sh
IDENTITY="${CODESIGN_IDENTITY:-$(find_identity "Apple Development")}"
IDENTITY="${IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP"
echo "Hotovo: $APP (podpis: $IDENTITY)"
