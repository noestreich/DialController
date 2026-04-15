# Dial Controller – Xcode Setup

## Neues Xcode-Projekt erstellen

1. Xcode öffnen → **File → New → Project**
2. **macOS → App** wählen, dann:
   - Product Name: `DialController`
   - Bundle Identifier: `de.oestreich.DialController`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - ⚠️ **"Include Tests" deaktivieren**

## Dateien einbinden

3. Alle `.swift`-Dateien aus `Sources/DialController/` in das Xcode-Projekt ziehen
   (die von Xcode erstellten `ContentView.swift` und `Assets.xcassets`-Einträge können gelöscht werden)

## Info.plist anpassen

4. Xcode zeigt die Info.plist meist als Property-Liste im Editor.
   Folgende Keys hinzufügen (falls nicht vorhanden):
   - `Application is agent (UIElement)` → `YES`
   - `Privacy - Input Monitoring Usage Description` → `"Dial Controller liest Eingaben des Ulanzi Dial..."`

## Entitlements konfigurieren

5. In den **Target Settings → Signing & Capabilities**:
   - **App Sandbox** deaktivieren (sonst kann IOHIDManager nicht seizen)
   - Eigene Entitlements-Datei (`DialController.entitlements`) aus diesem Verzeichnis verwenden

## Berechtigungen beim ersten Start

Beim ersten Start erscheinen zwei Systemdialoge:

- **Bedienungshilfen / Accessibility**: Erlauben (für CGEventPost)
- **Input-Überwachung**: Erlauben (für HID-Zugriff)
  → System Settings → Privacy & Security → Input Monitoring → DialController ✓

## Verwendung

- Menüleisten-Icon klicken → Konfigurationsfenster öffnet sich
- **„Button lernen"** drücken → gewünschten Button am Dial drücken → er erscheint in der Liste
- Shortcut-Feld klicken → Tastenkombination drücken → wird gespeichert
- Das Dial-Drehrad wird als "Dial +" (rechts) und "Dial -" (links) erkannt

## Bekannte Einschränkungen

- Kein App-Sandbox: App kann nicht im Mac App Store veröffentlicht werden (kein Problem für persönlichen Gebrauch)
- Wenn die App nicht läuft, sendet das Dial wieder normale Tastatur-Events ans System
