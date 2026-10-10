# Pin shortcut and plain-language help verification

## Behavior

The global pin shortcut removes the foremost visible Fuwa picture under the pointer, including click-through follow-original pictures. Elsewhere it retains the existing front-window pin/unpin behavior. Menu and button actions retain their existing targeting. The pointer and exact pin UUID are captured synchronously; if that pin disappears before the task runs, removal is a no-op rather than pinning another window.

Normal windows and Fuwa controls block pictures behind them. Hidden pictures are absent from the on-screen inventory. Targeting reuses the existing source-selection system-surface classification and focused-system-UI boundary. Real WindowServer acceptance exposed full-display transparent Dock and screen-recording helper surfaces with alpha 1; treating their bounds as ordinary occlusion would prevent this feature from working. Keep this case in regression coverage.

Reviewed all UI help and explanatory copy. Rewrote 21 entries in all seven languages to name actions and their results: pin/unpin, show/hide, pause/resume, Dock, permission, picture quality, position, crop, desktop/app visibility, frame rate, idle detection and failed-update recovery. Existing clear labels remain. Corrected the frame-rate explanation to include its remembered default for new pins from the same application. Help remains a neutral hover-only native image.

## Checks

- macOS 27.0.1, Apple Silicon. Strict native suite passed: 70 tests in 16 suites; the explicit live probe is disabled during the default suite.
- Explicit native WindowServer probe passed with FUWA_SHORTCUT_WINDOW_QA=1: generated click-through picture, overlapping pictures, an occluding ordinary surface, hidden pictures, coordinate conversion and unchanged foreground application. It does not move the actual pointer, send hardware shortcuts, capture user windows or request recording permission.
- Strict Release logic tests passed: 161 assertions, including 14 new pointer-targeting cases and seven-language key/placeholder parity.
- Seven-language offscreen rendering passed. Simplified Chinese and German settings were visually inspected; neutral help icons and existing row layout remain intact. Offscreen rendering does not prove native tooltip expansion.
- Strict Release application packaging, stable signature verification and embedded Sparkle loading passed. The preview designated requirement matches the running development application.
- After confirming there were zero active pictures, replaced and launched the development bundle. Native accessibility shows the new seven-language help keys and image roles; the visible Simplified Chinese settings retain gray help icons. The installed application was not replaced.

Physical pointer-dwell tooltip acceptance and the complete hardware-shortcut-to-live-session-removal path are not claimed by these probes. No version bump, release publication, updater metadata change or installed /Applications bundle replacement is part of this change.
