<div align="center">
  <img src="docs/images/app-icon.png" width="112" alt="Icône de Fuwa">
  <h1>Fuwa</h1>
  <p>Gardez vos fenêtres au premier plan sur Mac.</p>
  <p>
    <a href="https://fuwa.yuxino.cn"><strong>Site officiel</strong></a>
    · <a href="https://github.com/yuxino/fuwa/releases"><strong>Voir les versions</strong></a>
  </p>
  <p>
    <a href="README.md">简体中文</a>
    · <a href="README_ZH_TW.md">繁體中文</a>
    · <a href="README_EN.md">English</a>
    · <a href="README_JA.md">日本語</a>
    · <a href="README_KO.md">한국어</a>
    · <strong>Français</strong>
    · <a href="README_DE.md">Deutsch</a>
  </p>
  <p>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/github/v/release/yuxino/fuwa?style=flat&amp;logo=github&amp;logoColor=white" alt="Dernière version"></a>
    <a href="https://github.com/yuxino/fuwa/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://img.shields.io/github/actions/workflow/status/yuxino/fuwa/ci.yml?style=flat&amp;logo=githubactions&amp;logoColor=white&amp;branch=main&amp;event=push&amp;label=CI" alt="État de la CI sur main"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat&amp;logo=opensourceinitiative&amp;logoColor=white" alt="Licence MIT"></a>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/badge/macOS-14%2B-555?style=flat&amp;logo=apple&amp;logoColor=white" alt="macOS 14+"></a>
  </p>
</div>

Fuwa permet d’épingler des fenêtres sur macOS. Gardez une vue en direct d’une image, d’un document ou d’un tutoriel au premier plan pendant que vous travaillez dans une autre application. Les clics traversent la vue épinglée pour atteindre l’application située dessous.

## Utilisation

1. Lancez Fuwa et placez la fenêtre souhaitée au premier plan.
2. Appuyez sur `⌥⌘P` pour l’épingler. Appuyez à nouveau lorsque la même fenêtre source est au premier plan pour la détacher.
3. Gérez les fenêtres épinglées et mettez leur image en pause ou reprenez la lecture depuis la barre des menus.

## Fonctionnalités

- Épinglez plusieurs fenêtres et mettez leur image en pause sans interrompre les fenêtres d’origine.
- Prise en charge des fenêtres d’applications et des aperçus système d’images et de documents.
- Raccourci clavier personnalisable.
- Interface en chinois simplifié, chinois traditionnel, anglais, japonais, coréen, français et allemand. Suivez la langue du système ou choisissez-en une dans les réglages.
- Chaque fenêtre conserve sa qualité d’origine au départ. Cliquez sur sa roue dentée pour réduire sa qualité et sa consommation de mémoire.
- Épinglez ou choisissez une fenêtre et mettez son image en pause depuis la barre des menus. Les réglages s’ouvrent dans la fenêtre principale.
- Choisissez d’afficher ou non l’icône dans le Dock. Ce réglage ne ferme pas les fenêtres ouvertes.
- Les vues qui suivent leur fenêtre source laissent passer les clics. Les fenêtres de référence indépendantes peuvent être déplacées, redimensionnées et recadrées séparément.
- Les images et les métadonnées des fenêtres restent sur votre ordinateur, sans envoi, analyse ni télémétrie.
- Vérifiez, téléchargez et installez les mises à jour après vérification de leur signature Ed25519 depuis les réglages. Aucune vérification ni installation automatique en arrière-plan.

## Configuration requise

Fuwa 1.2.0 propose des fenêtres de référence indépendantes, la sélection d’une zone, le masquage et l’affichage ainsi que des conditions de visibilité. Consultez le [guide d’utilisation (anglais et chinois simplifié)](docs/floating-reference.md).

- macOS 14 ou version ultérieure. Le paquet distribué inclut arm64 (Apple Silicon) et x86_64 (Intel). La validation sur un Mac Intel physique reste à effectuer.
- Autorisation d’enregistrement de l’écran, demandée uniquement lors de la première tentative d’épinglage.

## Installation

Téléchargez `Fuwa-<version>.dmg` depuis [GitHub Releases](https://github.com/yuxino/fuwa/releases), ouvrez-le et faites glisser `Fuwa.app` vers le dossier `Applications` situé à côté. Chaque paquet public est accompagné d’un fichier de contrôle `.sha256` :

```sh
cd ~/Downloads
shasum -a 256 -c "Fuwa-<version>.dmg.sha256"
```

Remplacez `<version>` par le numéro de version réel. Les versions v0.1.4 et antérieures nécessitent une mise à jour manuelle vers v0.1.5 ou une version ultérieure une première fois. Ensuite, choisissez « Rechercher une mise à jour » dans les réglages de Fuwa. L’application n’accepte que son flux GitHub fixe et les paquets vérifiés par la clé publique intégrée. En cas d’échec de la vérification, elle n’installe pas de paquet non signé.

Le paquet macOS utilise une identité de signature locale maintenue par le projet, sans signature Apple Developer ID ni notarisation Apple. Si macOS bloque l’ouverture, vérifiez la provenance et le SHA-256, puis suivez les [instructions d’Apple](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac). Ne désactivez pas les protections du système.

## Compiler depuis les sources

Fuwa utilise Swift, SwiftUI/AppKit, ScreenCaptureKit et Sparkle.

```sh
git clone https://github.com/yuxino/fuwa.git
cd fuwa
./scripts/setup-local-signing.sh
./scripts/install-app.sh
```

[Confidentialité](PRIVACY.md) · [Contribuer](CONTRIBUTING.md) · [Sécurité](SECURITY.md) · [Implémentation indépendante](docs/independent-implementation.md)

## Licence

[MIT](LICENSE) © 2026 yuxino and Fuwa contributors
