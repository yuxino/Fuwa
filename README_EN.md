<div align="center">
  <img src="docs/images/app-icon.png" width="112" alt="Fuwa app icon">
  <h1>Fuwa</h1>
  <p>Pin windows on your Mac.</p>
  <p>
    <a href="https://fuwa.yuxino.cn"><strong>Official website</strong></a>
    · <a href="https://github.com/yuxino/fuwa/releases"><strong>View releases</strong></a>
  </p>
  <p>
    <a href="README.md">简体中文</a>
    · <a href="README_ZH_TW.md">繁體中文</a>
    · <strong>English</strong>
    · <a href="README_JA.md">日本語</a>
    · <a href="README_KO.md">한국어</a>
    · <a href="README_FR.md">Français</a>
    · <a href="README_DE.md">Deutsch</a>
  </p>
  <p>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/github/v/release/yuxino/fuwa?style=flat&amp;logo=github&amp;logoColor=white" alt="Latest release"></a>
    <a href="https://github.com/yuxino/fuwa/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://img.shields.io/github/actions/workflow/status/yuxino/fuwa/ci.yml?style=flat&amp;logo=githubactions&amp;logoColor=white&amp;branch=main&amp;event=push&amp;label=CI" alt="CI status on main"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat&amp;logo=opensourceinitiative&amp;logoColor=white" alt="MIT license"></a>
    <a href="https://github.com/yuxino/fuwa/releases/latest"><img src="https://img.shields.io/badge/macOS-14%2B-555?style=flat&amp;logo=apple&amp;logoColor=white" alt="macOS 14+"></a>
  </p>
</div>

Fuwa is a macOS window pinning app. Keep an image, document, or tutorial in view while you work in another app. The picture can follow its source window or sit wherever you need it as an independent reference.

## Use

1. Launch Fuwa and follow Getting Started to allow Screen Recording. You can skip the guide and reopen it from the sidebar later.
2. Choose a window from the thumbnail list, or bring the target window to the front and press `⌥⌘P` to pin it.
3. Manage pictures and pause or resume playback from the menu bar. Open the gear controls to switch a picture to Reference Window mode.

## Features

- Pin multiple app windows or system previews of images and documents. Pausing their pictures leaves the original windows running.
- Pictures that follow their source let clicks pass through. Independent references can be moved, resized, cropped, and arranged in a corner of their current display.
- Adjust a reference’s opacity; pointing at it restores full clarity. With hover enlargement enabled, a larger preview appears beside it when there is enough room.
- Hide or show all pictures whenever needed. Optionally enable **Hold ⌃⌥ to hide pictures** in Settings; releasing the keys restores the previous visibility. This setting is off by default.
- Customize the shortcuts for pinning windows and hiding or showing pictures.
- Interface languages: English, Simplified Chinese, Traditional Chinese, Japanese, Korean, French, and German. Follow the system language or choose one in Settings.
- Each pinned window starts at original quality. Click its gear to lower that window’s quality and use less memory.
- Common actions are available from the menu bar; Settings open in the main window. Choose whether Fuwa appears in the Dock without closing open windows.
- Window pixels and metadata stay on your computer, with no uploads, analytics, or telemetry. Accessibility permission is not required.
- Check, download, and install Ed25519-verified updates from Settings. No automatic background checks or installs.

See the [workflow guide](docs/floating-reference.md) for reference sizes, double-clicking to return to the source app, visibility rules, and other controls.

## Requirements

- macOS 14 or later; the release archive includes arm64 (Apple silicon) and x86_64 (Intel). Physical Intel Mac acceptance is still pending.
- Screen Recording permission, requested when you choose to authorize it in Getting Started or first try to pin a window. Launching Fuwa does not automatically prompt for permission.

## Install

Download `Fuwa-<version>.dmg` from [GitHub Releases](https://github.com/yuxino/fuwa/releases), open it, and drag `Fuwa.app` into the Applications folder beside it. Every public package has a matching `.sha256` file:

```sh
cd ~/Downloads
shasum -a 256 -c "Fuwa-<version>.dmg.sha256"
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

## Community

[LINUX DO](https://linux.do) · A community for tech enthusiasts.

## License

[MIT](LICENSE) © 2026 yuxino and Fuwa contributors
