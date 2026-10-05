# Fuwa · MyGo rewrite

An isolated, native-Go rewrite of Fuwa using [egoist/mygo](https://github.com/egoist/mygo). **Experimental branch: `rewrite/mygo`. Not the stable release.** [简体中文](README_ZH.md)

The Swift application is replaced, not embedded or launched as a helper. MyGo owns the application lifecycle, native Go UI, windows, menus, global shortcuts and updater. A new Objective-C adapter supplies ScreenCaptureKit, public Accessibility matching and macOS login registration. There is no web frontend.

## Try it

On macOS 14+, with Go 1.27.1+ and Xcode Command Line Tools:

```sh
git clone --branch rewrite/mygo https://github.com/yuxino/Fuwa.git Fuwa-MyGo
cd Fuwa-MyGo
go mod tidy
go test -race ./...
./scripts/build-mygo.sh
open 'build/Fuwa MyGo.app'
```

The workflow **MyGo rewrite** produces `Fuwa-MyGo-preview`, containing the universal application ZIP, SHA-256, native UI fixture screenshots and test output. Screenshots are rendered from the actual Go view with test data, **not a recording of successful screen capture**.

This app is named **Fuwa MyGo**, with bundle ID `app.yuxino.fuwa.mygo` and independent preferences and permissions. It neither installs over nor migrates the stable Fuwa. The preview is ad-hoc signed, not Developer ID signed or notarized. Do not disable Gatekeeper or system-wide protections.

## Use

Bring the source window to the front and press **⌥⌘P**. Repeat on the same source to unpin. The mirror is click-through; manage it from the menu bar, main window or pin controls. Up to eight windows can be pinned. Use **Freeze**, **Resume** and **Go to original**; the last complete frame is kept when its source closes or capture is interrupted.

Settings include a customizable shortcut, Dock visibility, launch at login, System/English/Simplified Chinese, permission status and manual signed updates. Closing the main window leaves the menu bar running. When “Keep Fuwa in the Dock” is off, the Dock icon is present only while the main window is open.

Screen Recording is requested only for a pin attempt. Accessibility is requested only for **Go to original**. Captured pixels and window metadata are not written to disk or uploaded. Sleep, session deactivation, lock and permission revocation clear pins; waking does not restore them.

## Verification boundaries

Read [the feature and acceptance checklist](docs/mygo-rewrite.md). Unit tests and a successful build do not establish real-device parity. TCC dialogs, live capture, Quick Look, Spaces, multi-display/Retina, VoiceOver, login-item approval and Intel execution need interactive macOS acceptance. CPU/memory improvements have not been measured.

Manual updates use MyGo's Ed25519-verified package installer and the existing **public** verification key, with a separate `mygo-v` release prefix. They never consume the stable Swift/Sparkle appcast. No MyGo release is published by this branch or CI. Until one exists, checking reports that no signed MyGo release is available. Downloads and installation are one user-initiated cancellable operation rather than Sparkle's separate staging screens.

## Layout

- `internal/core`: deterministic selection, identities, session state and atomic preferences, with tests.
- `internal/native`: new macOS capture/permissions/Accessibility adapter; bounded frame mailbox and independent frozen images.
- `internal/view`: native MyGo interface and headless interaction/render tests.
- `main_darwin.go`: application orchestration; one shared tracker, privacy lifecycle, menus, shortcuts and manual updates.

Use the supplied build script: the upstream MyGo CLI forces `CGO_ENABLED=0`, whereas this app's ScreenCaptureKit adapter needs cgo. MyGo itself is unchanged and pinned to commit `bfb878510ce3e0f7ac684090137d5147ed4421ff`.

Historical Swift documentation remains under `docs/`; it is not the build instructions for this branch. Stable source is preserved on `main` and in Git history.

MIT · yuxino and Fuwa contributors
