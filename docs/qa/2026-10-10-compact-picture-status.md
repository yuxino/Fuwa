# Compact picture status and Fuwa 1.2.0 preparation

The user's screenshot showed an unclear inactivity option and excessively wide popovers. Both management and floating options now share a 320-point preferred width (previously 380); help uses 220 points (previously 300). Screen-edge limits and content-height scrolling remain in place.

Performance settings state the concrete result directly: static pictures use 1 fps until detected changes, and the optional “Picture unchanged” label appears at the upper left of the floating picture. Click help explains the existing 15-second threshold and disappearance on change. Labels, inline details and explanations cover all seven languages. Detection and capture policy are unchanged.

## Checks

- Strict native suite passed: 69 declared tests in 15 suites, 68 active with generated-source capture fixtures enabled. Only the unrelated virtual-display probe was disabled.
- Generated-window crop, hide/restore, independent reference positioning, idle reduction, paused-picture retention, source closure and teardown passed using an existing recording grant. These tests select generated WindowServer sources, not user work windows, and request no new permission.
- Seven-language native offscreen renders passed, including all three sections, long titles, narrow layouts and large text. The shorter sections retain their natural height and all tested layouts stay within their height caps.
- macOS-only checks, update-metadata fixtures and release-checksum parser tests passed. The final public archive and signing/promotion evidence are separate release checks.
- Version is 1.2.0, build 24. Public notes in CHANGELOG are bilingual and product docs now describe the included reference workflows.

## Native fixture previews

These are offscreen native renders with generated titles and data. They do not show user windows or prove physical pointer interaction.

![Compact performance options](2026-10-10-compact-picture-status/performance.png)

![Narrow explanation](2026-10-10-compact-picture-status/help.png)

![Small German performance layout](2026-10-10-compact-picture-status/small-performance.png)

Existing [reference-workflow evidence](2026-10-10-floating-reference.md) and [settings-help interaction evidence](2026-10-10-natural-interactions.md) record additional scope and limits. Physical Intel, external-display hardware, macOS 14 and a complete updater installation are not claimed.
