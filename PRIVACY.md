# Fuwa Privacy Policy

Last updated: October 9, 2026

Fuwa is a local-first macOS utility with no analytics, advertising, telemetry, or user account system. It makes network requests only after you explicitly choose `Check for Updates`: Fuwa retrieves its public signed update feed and, if you approve an available update, its package from GitHub Releases. These requests do not include window pixels, window metadata, filenames, shortcut settings, or other Fuwa content.

## Data Fuwa processes

On macOS, when you create a pin, Fuwa uses Apple's ScreenCaptureKit and window-list APIs to process:

- pixels from the window you selected;
- the source window's identifier, owning process, title, bounds, and capture state as needed to select and manage that pin;
- a temporary WindowServer and ScreenCaptureKit inventory of visible and live windows, including identifiers, owning processes and apps, bundle identifiers, bounds, layer, alpha, and capture availability, so Fuwa can distinguish the intended front window from overlays and keep a live source aligned;
- your configured keyboard shortcut and launch-at-login preference.

Window pixels and window metadata are used only on your computer to provide the requested feature. Fuwa does not transmit them. Fuwa does not record audio, keystrokes, clicks, or clipboard contents.

## Storage and retention

- On macOS, live frames are held only as needed to render a pin. A paused pin keeps its last complete frame in memory and never writes it to disk.
- Window inventories are transient snapshots. Fuwa does not persist or log them.
- Unpinning clears any retained frame.
- Locking the screen, sleeping the computer, switching users, or quitting Fuwa stops active mirroring immediately. On macOS, Screen Recording revocation also clears captured pixels when detected.
- Language, picture quality, Dock visibility, the keyboard shortcut, and the launch-at-login preference are stored locally using system preferences and services.

Fuwa does not restore third-party window content after a privacy boundary. The updater may store a verified package temporarily while installing it and removes or replaces that staging data through the native Sparkle lifecycle. macOS may create diagnostic reports according to your system settings; Fuwa does not collect or transmit those reports.

## Permissions

### Screen Recording

Required only on macOS to capture the window you explicitly pin. Fuwa requests it when you first attempt to pin, not at launch.

Fuwa does not request Accessibility, camera, microphone, Input Monitoring, Automation, Contacts, Location, or Photos access.

## Third parties

Fuwa contains no analytics SDKs. GitHub serves the public update feeds and packages; as with an ordinary HTTPS download, GitHub receives network metadata such as your IP address and request headers under its own privacy terms. Apple provides the macOS permission and launch-at-login services, governed by your operating-system settings and platform policies.

## Changes

Material changes to this policy will be recorded in the repository and reflected by the date above.

## Questions

Open a discussion or issue in the [Fuwa repository](https://github.com/yuxino/fuwa) for privacy questions. Do not include sensitive window content or private information in a public issue.
