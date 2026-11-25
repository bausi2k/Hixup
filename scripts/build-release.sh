#!/bin/bash
# Baut Hixup im Release-Modus und packt ein DMG nach dist/.
#
# Ohne Umgebungsvariablen entsteht ein UNSIGNIERTES DMG (nur zum Testen; der Hintergrunddienst
# laesst sich so nicht zuverlaessig registrieren). Fuer die Verteilung:
#   DEVELOPER_ID   Name der Signaturidentitaet, z. B. "Developer ID Application: Name (TEAMID)"
#   TEAM_ID        Apple Team ID
#   NOTARY_PROFILE Name eines mit `xcrun notarytool store-credentials` gespeicherten Profils
# Sind DEVELOPER_ID und TEAM_ID gesetzt, wird signiert; mit NOTARY_PROFILE zusaetzlich notarisiert.
set -euo pipefail

cd "$(dirname "$0")/.."
DERIVED=.build/release
DIST=dist
APP="$DERIVED/Build/Products/Release/Hixup.app"
VERSION=$(grep -m1 MARKETING_VERSION project.yml | sed -E 's/.*"([^"]+)".*/\1/')
DMG="$DIST/Hixup-$VERSION.dmg"

xcodegen generate -q

SIGN_ARGS=(CODE_SIGNING_ALLOWED=NO)
if [[ -n "${DEVELOPER_ID:-}" && -n "${TEAM_ID:-}" ]]; then
    SIGN_ARGS=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$DEVELOPER_ID" "DEVELOPMENT_TEAM=$TEAM_ID" OTHER_CODE_SIGN_FLAGS=--timestamp)
fi

xcodebuild -project Hixup.xcodeproj -scheme HixupApp -configuration Release \
    -derivedDataPath "$DERIVED" "${SIGN_ARGS[@]}" build

rm -rf "$DIST" && mkdir -p "$DIST/staging"
cp -R "$APP" "$DIST/staging/"
ln -s /Applications "$DIST/staging/Applications"
hdiutil create -volname "Hixup" -srcfolder "$DIST/staging" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DIST/staging"

if [[ -n "${DEVELOPER_ID:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "Fertig: $DMG"
