# Natural macOS interactions

The existing neutral SwiftUI/AppKit surfaces stay intact. This pass addresses the user's two screenshots: settings help icons had no useful hover feedback, settings groups were too broad, and window options had indirect controls and excessive blank space.

- Settings: group language, keyboard shortcuts, startup and Dock, permissions, and updates separately. Keep explanatory text behind accessible help controls.
- Help: use real native buttons with visible pointer feedback, native hover tooltips and click/keyboard-accessible explanations. Close help on Escape, outside interaction, disabling, or removal. Help within floating controls must not dismiss its parent.
- Window options: keep playback and tab navigation reachable; make position a direct two-choice control, adapt region actions to the current crop, distinguish closing controls from removing a pin, and size the panel to its content within the available display.
- Main window: give the empty state an actionable starting point; keep routine shortcut guidance concise when pins already exist. Preserve busy, error, paused and hidden semantics.

Verification uses strict native builds, existing lifecycle/capture regressions, native help-control interaction tests, seven-language offscreen layouts, and a signed preview. Running source windows and user pins remain untouched during development.

API references: [NSPopover](https://developer.apple.com/documentation/appkit/nspopover), [SwiftUI hover](https://developer.apple.com/documentation/swiftui/view/onhover(perform:)).
