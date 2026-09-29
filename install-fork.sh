#!/bin/zsh
# Baut den Fork, ersetzt /Applications/DockDoor.app und startet neu.
# Nimmt die Homebrew-Cask-Version aus dem Weg, damit "brew upgrade" den Fork
# nicht wieder überschreibt. Einstellungen (UserDefaults) bleiben erhalten.
set -euo pipefail
cd "$(dirname "$0")"

./build-fork.sh

osascript -e 'tell application "DockDoor" to quit' 2>/dev/null || true
sleep 1
pkill -x DockDoor 2>/dev/null || true

if brew list --cask dockdoor >/dev/null 2>&1; then
  brew uninstall --cask dockdoor
fi
rm -rf /Applications/DockDoor.app
cp -R build/DockDoor.app /Applications/DockDoor.app

# Sparkle darf den Fork nicht durch das Upstream-Release ersetzen.
defaults write com.ethanbills.DockDoor SUEnableAutomaticChecks -bool false
defaults write com.ethanbills.DockDoor SUAutomaticallyUpdate -bool false

open /Applications/DockDoor.app
echo "Installiert. macOS fragt wegen der neuen Signatur einmal neu nach Bedienungshilfen und Bildschirmaufnahme."
