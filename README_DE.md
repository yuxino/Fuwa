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

Fuwa hält Fenster auf macOS im Vordergrund. Behalten Sie ein Livebild einer Abbildung, eines Dokuments oder einer Anleitung im Blick, während Sie in einer anderen App arbeiten. Klicks werden durch das angeheftete Bild an die darunterliegende App weitergegeben.

## Verwendung

1. Starten Sie Fuwa und bringen Sie das gewünschte Fenster in den Vordergrund.
2. Drücken Sie `⌥⌘P`, um es anzuheften. Drücken Sie das Tastenkürzel erneut, während dasselbe Quellfenster im Vordergrund ist, um es zu lösen.
3. Verwalten Sie angeheftete Fenster über die Menüleiste und pausieren Sie deren Bild oder setzen Sie die Wiedergabe fort.

## Funktionen

- Mehrere Fenster gleichzeitig anheften und ihre Bilder pausieren, während die ursprünglichen Fenster weiterlaufen.
- Unterstützung für App-Fenster und die Systemvorschau von Bildern und Dokumenten.
- Anpassbares Tastenkürzel.
- Oberfläche auf vereinfachtem Chinesisch, traditionellem Chinesisch, Englisch, Japanisch, Koreanisch, Französisch und Deutsch. Folgen Sie der Systemsprache oder wählen Sie eine Sprache in den Einstellungen.
- Jedes Fenster startet mit der ursprünglichen Bildqualität. Über das Zahnrad daneben können Sie die Qualität dieses Fensters und damit den Speicherbedarf verringern.
- Fenster über die Menüleiste anheften oder auswählen und deren Bild pausieren. Die Einstellungen öffnen sich im Hauptfenster.
- Wählen Sie, ob Fuwa im Dock erscheint. Der Schalter ändert nur das Symbol und schließt keine geöffneten Fenster.
- Bilder, die ihrem Quellfenster folgen, lassen Klicks durch. Unabhängige Referenzfenster lassen sich separat verschieben, skalieren und auf einen Bildausschnitt begrenzen.
- Fensterbilder und Metadaten bleiben auf Ihrem Computer. Es gibt keine Uploads, Analysen oder Telemetrie.
- Updates in den Einstellungen suchen, herunterladen und nach Prüfung der Ed25519-Signatur installieren. Keine automatische Suche oder Installation im Hintergrund.

## Voraussetzungen

Fuwa 1.2.0 bietet unabhängige Referenzfenster, Bereichsauswahl, Ein- und Ausblenden sowie Sichtbarkeitsregeln. Einzelheiten finden Sie in der [Anleitung (Englisch und vereinfachtes Chinesisch)](docs/floating-reference.md).

- macOS 14 oder neuer. Das veröffentlichte Paket enthält arm64 (Apple Silicon) und x86_64 (Intel). Die Prüfung auf einem physischen Intel-Mac steht noch aus.
- Berechtigung zur Bildschirmaufnahme, die erst beim ersten Versuch, ein Fenster anzuheften, angefordert wird.

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
