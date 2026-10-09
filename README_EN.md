<div align="center">
  <img src="docs/images/app-icon.png" width="112" alt="Fuwa app icon">
  <h1>Fuwa</h1>
  <p>Pin windows on your Mac.</p>
  <p>
    <a href="https://fuwa.yuxino.cn"><strong>Official website</strong></a>
    · <a href="https://github.com/yuxino/fuwa/releases"><strong>View releases</strong></a>
    · <a href="README.md">简体中文</a>
  </p>
  <p>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/github/v/release/yuxino/fuwa?style=flat&amp;logo=github&amp;logoColor=white" alt="Latest release"></a>
    <a href="https://github.com/yuxino/fuwa/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://img.shields.io/github/actions/workflow/status/yuxino/fuwa/ci.yml?style=flat&amp;logo=githubactions&amp;logoColor=white&amp;branch=main&amp;event=push&amp;label=CI" alt="CI status on main"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat&amp;logo=opensourceinitiative&amp;logoColor=white" alt="MIT license"></a>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/badge/macOS-14%2B-555?style=flat&amp;logo=apple&amp;logoColor=white" alt="macOS 14+"></a>
  </p>
</div>

Fuwa is a macOS window pinning app. Keep a live view of an image, document, or tutorial on top while you work in another app. The pinned view lets clicks pass through to the app underneath.

## Use

1. Launch Fuwa and bring the target window to the front.
2. Press `⌥⌘P` to pin it. Press the shortcut again while the same source is in front to unpin.
3. Manage pins and live or frozen state from the menu bar.

## Features

- Pin multiple windows and freeze frames.
- Support for application windows and system previews of images and documents.
- Customizable keyboard shortcut.
- Choose a capture limit of 4 (default), 9, or 16 million pixels, or keep native resolution. Higher limits preserve more detail and use more memory.
- Choose whether Fuwa stays in the Dock. When off, its icon appears only while the main window is open; the menu bar remains available.
- Mirrors pass mouse input through; `Go to Original Window` activates and raises the real source window.
- Window pixels and metadata stay on your computer, with no uploads, analytics, or telemetry.
- Check, download, and install Ed25519-verified updates from Settings. No automatic background checks or installs.

## Requirements

- macOS 14 or later; the release archive includes arm64 (Apple silicon) and x86_64 (Intel). Physical Intel Mac acceptance is still pending.
- Screen Recording permission, requested only on the first pin attempt.
- Accessibility permission, requested only for `Go to Original Window`.

## Install

Download `Fuwa-<version>.zip` from [GitHub Releases](https://github.com/yuxino/fuwa/releases), extract it, and move `Fuwa.app` to `/Applications`. Every public package has a matching `.sha256` file:

```sh
cd ~/Downloads
shasum -a 256 -c "Fuwa-<version>.zip.sha256"
```

Replace `<version>` with the actual version number. Versions v0.1.4 and earlier need one manual upgrade to v0.1.5 or later. After that, select `Check for Updates` in Fuwa Settings. Fuwa accepts only its fixed GitHub feed and packages verified by the embedded public key; verification failure never falls back to unsigned installation.

The macOS package uses the project's maintained local signing identity, not Apple Developer ID signing or notarization. If macOS blocks it, verify the source and SHA-256 and follow [Apple's instructions](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac), rather than weakening system security.

## Build from source

Fuwa uses Swift, SwiftUI/AppKit, ScreenCaptureKit, and Sparkle.

```sh
git clone https://github.com/yuxino/fuwa.git
cd fuwa
./scripts/setup-local-signing.sh
./scripts/install-app.sh
```

[Privacy](PRIVACY.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Independent implementation](docs/independent-implementation.md)

## License

[MIT](LICENSE) © 2026 yuxino and Fuwa contributors
