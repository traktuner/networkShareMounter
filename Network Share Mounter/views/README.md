# SwiftUI Einstellungsdialog

Dieses Verzeichnis enthält die neuen SwiftUI-basierten Einstellungsansichten für die Network Share Mounter App. Die Implementierung folgt strikt den macOS Human Interface Guidelines und bietet eine moderne, flache Alternative zu den bisherigen NSViewController-basierten Einstellungen.

## Struktur

- `SettingsView.swift`: Hauptansicht mit Seitenleiste und Navigation
- `NetworkSharesView.swift`: Konfiguration für Netzwerk-Shares
- `AuthenticationView.swift`: Authentifizierungseinstellungen inkl. Kerberos-Optionen
- `GeneralSettingsView.swift`: Allgemeine App-Einstellungen
- `SettingsWindowManager.swift`: Manager für das Einstellungsfenster
- `AppDelegate+SettingsIntegration.swift`: Integration mit AppDelegate

## Integration

Um das neue Einstellungsfenster zu verwenden, muss in `AppDelegate.swift` die folgende Zeile in `applicationDidFinishLaunching` hinzugefügt werden:

```swift
configureSettingsIntegration()
```

Die Einstellungen können dann über den Menüpunkt "Einstellungen..." oder durch direkten Aufruf von `AppDelegate.openSettings()` geöffnet werden.

## Design-Prinzipien

- **Minimalistisches Design**: Flache, aufgeräumte Oberfläche ohne überflüssige visuelle Elemente
- **Exakte Einhaltung von Apple-Standards**: Design gemäß aktuellen macOS-Einstellungen
- **Konsistente Abstände und Größen**: Abmessungen und Abstände entsprechen Apple-Vorgaben
- **Klare visuelle Hierarchie**: Gut strukturierte Inhaltsdarstellung
- **Responsive Animation**: Subtile Animationen für bessere Benutzererfahrung
- **Volle Barrierefreiheit**: Unterstützung von VoiceOver und anderen Hilfstechnologien

## Nächste Schritte

1. Anbindung an das bestehende Datenmodell
2. Implementierung der Logik für Netzwerk-Share-Verwaltung
3. Kerberos-Integration
4. Tests und Qualitätssicherung

## Designentscheidungen

Die Anwendung verzichtet bewusst auf:
- Überflüssige Rahmen und Abgrenzungen
- Übermäßige visuelle Gestaltungselemente
- Komplexe Verschachtelungen von Ansichten

Stattdessen wird ein flacher, minimalistischer Stil verwendet, der die Inhalte in den Vordergrund stellt und den neuesten macOS-Design-Richtlinien entspricht.

## Screenshots

*Screenshots werden folgen, sobald alle Komponenten implementiert sind.* 