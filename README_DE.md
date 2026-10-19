<div align="center">
  <img src="docs/images/app-icon.png" width="112" alt="Fuwa-App-Symbol">
  <h1>Fuwa</h1>
  <p>Fenster auf dem Mac im Vordergrund halten.</p>
  <p>
    <a href="https://fuwa.yuxino.cn"><strong>Offizielle Website</strong></a>
    · <a href="https://github.com/yuxino/fuwa/releases"><strong>Versionen ansehen</strong></a>
  </p>
  <p>
    <a href="README.md">简体中文</a>
    · <a href="README_ZH_TW.md">繁體中文</a>
    · <a href="README_EN.md">English</a>
    · <a href="README_JA.md">日本語</a>
    · <a href="README_KO.md">한국어</a>
    · <a href="README_FR.md">Français</a>
    · <strong>Deutsch</strong>
  </p>
  <p>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/github/v/release/yuxino/fuwa?style=flat&amp;logo=github&amp;logoColor=white" alt="Neueste Version"></a>
    <a href="https://github.com/yuxino/fuwa/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://img.shields.io/github/actions/workflow/status/yuxino/fuwa/ci.yml?style=flat&amp;logo=githubactions&amp;logoColor=white&amp;branch=main&amp;event=push&amp;label=CI" alt="CI-Status auf main"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat&amp;logo=opensourceinitiative&amp;logoColor=white" alt="MIT-Lizenz"></a>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/badge/macOS-14%2B-555?style=flat&amp;logo=apple&amp;logoColor=white" alt="macOS 14+"></a>
  </p>
</div>

Fuwa hält Fenster auf macOS im Vordergrund. Behalten Sie ein Bild, ein Dokument oder eine Anleitung im Blick, während Sie in einer anderen App arbeiten. Das Bild kann seinem Quellfenster folgen oder als unabhängiges Referenzfenster dort stehen, wo Sie es brauchen.

## Verwendung

1. Starten Sie Fuwa und erlauben Sie die Bildschirmaufnahme über „Erste Schritte“. Sie können die Anleitung überspringen und später über die Seitenleiste wieder öffnen.
2. Wählen Sie ein Fenster aus der Liste mit Vorschaubildern oder bringen Sie es in den Vordergrund und drücken Sie `⌥⌘P`, um es anzuheften.
3. Verwalten Sie die Bilder über die Menüleiste und pausieren Sie die Wiedergabe oder setzen Sie sie fort. Öffnen Sie die Steuerelemente über das Zahnrad, um zum Referenzfenster zu wechseln.

## Funktionen

- Mehrere App-Fenster oder Systemvorschauen von Bildern und Dokumenten anheften. Beim Pausieren ihrer Bilder laufen die ursprünglichen Fenster weiter.
- Bilder, die ihrem Quellfenster folgen, lassen Klicks durch. Unabhängige Referenzfenster lassen sich verschieben, skalieren, zuschneiden und in einer Ecke ihres jeweiligen Bildschirms anordnen.
- Passen Sie die Deckkraft einer Referenz an; unter dem Mauszeiger wird sie vollständig deckend. Bei aktivierter Vergrößerung erscheint daneben eine größere Vorschau, sofern genug Platz vorhanden ist.
- Alle Bilder jederzeit aus- oder einblenden. In den Einstellungen können Sie das Ausblenden beim Gedrückthalten von `⌃⌥` aktivieren; beim Loslassen gilt wieder der vorherige Sichtbarkeitszustand. Diese Option ist standardmäßig aus.
- Tastenkürzel zum Anheften sowie zum Aus- und Einblenden anpassen.
- Oberfläche auf vereinfachtem Chinesisch, traditionellem Chinesisch, Englisch, Japanisch, Koreanisch, Französisch und Deutsch. Folgen Sie der Systemsprache oder wählen Sie eine Sprache in den Einstellungen.
- Jedes Fenster startet mit der ursprünglichen Bildqualität. Über das Zahnrad daneben können Sie die Qualität dieses Fensters und damit den Speicherbedarf verringern.
- Häufige Aktionen sind über die Menüleiste erreichbar; die Einstellungen öffnen sich im Hauptfenster. Wählen Sie, ob Fuwa im Dock erscheint, ohne geöffnete Fenster zu schließen.
- Fensterbilder und Metadaten bleiben auf Ihrem Computer. Es gibt keine Uploads, Analysen oder Telemetrie. Eine Berechtigung für Bedienungshilfen ist nicht erforderlich.
- Updates in den Einstellungen suchen, herunterladen und nach Prüfung der Ed25519-Signatur installieren. Keine automatische Suche oder Installation im Hintergrund.

Größen für Referenzfenster, die Rückkehr zur Quell-App per Doppelklick, Sichtbarkeitsregeln und weitere Steuerelemente beschreibt die [Anleitung (Englisch und vereinfachtes Chinesisch)](docs/floating-reference.md).

## Voraussetzungen

- macOS 14 oder neuer. Das veröffentlichte Paket enthält arm64 (Apple Silicon) und x86_64 (Intel). Die Prüfung auf einem physischen Intel-Mac steht noch aus.
- Berechtigung zur Bildschirmaufnahme. Sie wird angefordert, wenn Sie sie unter „Erste Schritte“ erlauben oder erstmals ein Fenster anheften möchten. Beim bloßen Starten von Fuwa erscheint keine Berechtigungsanfrage.

## Installation

Laden Sie `Fuwa-<version>.dmg` von [GitHub Releases](https://github.com/yuxino/fuwa/releases) herunter, öffnen Sie die Datei und ziehen Sie `Fuwa.app` in den danebenliegenden Ordner `Applications`. Zu jedem öffentlichen Paket gehört eine `.sha256`-Prüfsummendatei:

```sh
cd ~/Downloads
shasum -a 256 -c "Fuwa-<version>.dmg.sha256"
```

Ersetzen Sie `<version>` durch die tatsächliche Versionsnummer. Bei v0.1.4 und älteren Versionen ist einmalig ein manuelles Update auf v0.1.5 oder neuer erforderlich. Danach können Sie in den Fuwa-Einstellungen „Nach Updates suchen“ wählen. Die App akzeptiert nur ihren festgelegten GitHub-Feed und Pakete, die mit dem eingebetteten öffentlichen Schlüssel geprüft wurden. Schlägt die Prüfung fehl, wird kein unsigniertes Paket installiert.

Das macOS-Paket nutzt eine vom Projekt gepflegte lokale Signaturidentität, keine Apple-Developer-ID-Signatur oder Apple-Notarisierung. Falls macOS das Öffnen blockiert, prüfen Sie die Herkunft und den SHA-256-Wert und folgen Sie den [Anweisungen von Apple](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac). Deaktivieren Sie keine Sicherheitsfunktionen des Systems.

## Aus dem Quellcode bauen

Fuwa verwendet Swift, SwiftUI/AppKit, ScreenCaptureKit und Sparkle.

```sh
git clone https://github.com/yuxino/fuwa.git
cd fuwa
./scripts/setup-local-signing.sh
./scripts/install-app.sh
```

[Datenschutz](PRIVACY.md) · [Mitwirken](CONTRIBUTING.md) · [Sicherheit](SECURITY.md) · [Unabhängige Implementierung](docs/independent-implementation.md)

## Lizenz

[MIT](LICENSE) © 2026 yuxino and Fuwa contributors
