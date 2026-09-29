# DockDoor-Fork: Snap Groups

Fork von [ejbills/DockDoor](https://github.com/ejbills/DockDoor), Branch `snap-groups`.
Ergänzt Windows-11-artige Snap Groups: Liegen zwei Fenster exakt in linker und
rechter Bildschirmhälfte (per macOS-Tiling oder Snap Assist), zeigt DockDoor beim
Hover über eine der beiden Apps eine zusätzliche Kachel mit beiden Fenstern
nebeneinander. Klick holt beide nach vorn. Gilt auch im Window Switcher.

## Was geändert wurde

| Datei | Änderung |
|---|---|
| `DockDoor/Utilities/Window Management/SnapGroups.swift` | Neu. Geometrische Erkennung (Toleranz 12 px wie Snap Assist), Live-Frames aus `CGWindowListCopyWindowInfo`, Partner aus dem Fenster-Cache, zusammengesetztes Vorschaubild mit kleinem Cache. |
| `WindowInfo.swift` | `snapGroupMembers`, `isSnapGroup`, `snapGroupEntry(left:right:primary:)`. `bringToFront()` hebt beide Fenster, `toggleMinimize()` minimiert beide. Synthetische ID mit gesetztem Top-Bit, damit Merges den Eintrag wiedererkennen. |
| `DockObserver.swift`, `DockObserver+CmdTab.swift`, `KeybindHelper.swift` | Gruppeneinträge werden an die Fensterliste angehängt (Cache-Anzeige, frischer Merge, Klick-Pfad, Cmd+Tab, Switcher). |
| `WindowPreviewHoverContainer.swift` | Gruppen ohne Live-Preview und ohne Drag. |
| `consts.swift`, `DockPreviewsSettingsView.swift`, `SettingsSearchCatalog.swift` | Schalter "Show snap groups" (Standard: an). |
| `DockDoorTests/SnapGroupsTests.swift` | Tests für die Paarbildung. |
| `DockDoor.xcodeproj/project.pbxproj` | Beide neuen Dateien registriert. |

Kein Datenaustausch mit Snap Assist nötig: beide Apps nutzen dieselbe Regel
"Fenster belegt eine Hälfte", die Gruppe löst sich auf, sobald ein Fenster
wegbewegt wird.

## Bauen

Der Code ist ohne Xcode geschrieben und nur geparst, nicht kompiliert. Erster
Build kann Tippfehler zeigen.

```
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -license accept
./install-fork.sh        # baut, ersetzt /Applications/DockDoor.app, startet neu
```

Beim ersten Build lädt Xcode die SPM-Abhängigkeiten (swift-syntax ist groß).
Tests: in Xcode Cmd+U oder

```
xcodebuild test -project DockDoor.xcodeproj -scheme DockDoor -destination 'platform=macOS' -only-testing:DockDoorTests/SnapGroupsTests
```

## Upstream nachziehen

```
git fetch upstream
git rebase upstream/main
```

## Offen

- Verhalten mit "Tiled windows have margins" (macOS-Rand): Fenster sind dann
  kleiner als die Hälfte, Toleranz greift nicht. Rand aus lassen.
- Aktionen außer Aktivieren/Minimieren (Schließen, Vollbild, Anordnen) wirken
  nur auf das Fenster der gehoverten App.
