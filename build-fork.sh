#!/bin/zsh
# Baut den DockDoor-Fork (Branch snap-groups) mit Xcode und signiert mit dem
# selbstsignierten Zertifikat "SnapAssist Dev" (siehe snap-assist/README.md),
# damit die Berechtigungen (Bedienungshilfen, Bildschirmaufnahme) über
# Neubauten hinweg erhalten bleiben.
#
# Voraussetzung: Xcode installiert und ausgewählt:
#   sudo xcode-select -s /Applications/Xcode.app
#   sudo xcodebuild -license accept
#
# Ergebnis: build/DockDoor.app
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${IDENTITY:-SnapAssist Dev}"
DERIVED="build/DerivedData"

# Ohne sudo xcode-select: Xcode direkt ansprechen.
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode fehlt oder ist nicht ausgewählt (xcode-select). Abbruch." >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "Zertifikat '$IDENTITY' nicht im Schlüsselbund. Anleitung: snap-assist/README.md" >&2
  exit 1
fi

# Erster Lauf lädt die SPM-Abhängigkeiten (Sparkle, Defaults, swift-syntax …).
xcodebuild -project DockDoor.xcodeproj -scheme DockDoor -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  build | tail -40

APP="$DERIVED/Build/Products/Release/DockDoor.app"
[ -d "$APP" ] || { echo "Build fehlgeschlagen, $APP fehlt." >&2; exit 1; }

rm -rf build/DockDoor.app
cp -R "$APP" build/DockDoor.app
codesign --verify --deep --strict build/DockDoor.app
echo "OK: build/DockDoor.app"
