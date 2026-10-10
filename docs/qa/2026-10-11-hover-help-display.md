# Hover help display acceptance

The native `toolTip` property was registered, but the user reported no visible help on hover. Registration/AX help alone did not establish that the tooltip displayed.

Help icons now use an explicit always-active tracking area and a passive, nonactivating child panel. After 250 ms inside the icon, the gray explanation appears; exit, detachment, hiding and copy changes cancel pending work and dismiss it. Unchanged SwiftUI updates retain the visible explanation. No click action, first-responder acceptance, link tint or cursor override is added.

Validation:

- Strict native default suite: 71 tests / 17 suites passed (visible fixture disabled).
- Explicit isolated native hover suite: 2 tests passed; actual disposable controls/child panel visibility, key-window/front-app retention, no press action, exit/detachment cancellation and unchanged-copy retention. Run the visible fixture separately with `FUWA_HELP_HOVER_QA=1 swift test --filter 'HelpInteractionTests|HelpHoverPresentationTests'`; other lifecycle suites deliberately close test windows and change focus.
- Strict Release package, stable signing requirement, framework loading and signed DMG mount/layout checks passed.
- Updated development bundle installed and launched after confirming zero user pins. Screen Recording remained granted.
- User physically hovered over the show/hide information icon and confirmed “能显示了”. This is the hover acceptance; earlier automated AX registration and synthetic clicks were not sufficient evidence.

All seven languages continue to share this control. The gray tooltip surface was visually inspected with the Simplified Chinese show/hide explanation.
