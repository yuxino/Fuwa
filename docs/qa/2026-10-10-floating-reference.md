# Floating reference verification — 2026-10-10

Scope: macOS reference placement, picture cropping, temporary visibility,
application/Space rules, frame-rate preferences and picture inactivity. Input
forwarding, exact source-window activation and virtual displays are deferred.
This record covers the development implementation and its usability pass. No
version, public release, installed-app replacement or recording-permission
change was made. A task-local app was packaged with the existing signing identity.

## Environment and automated checks

- Apple Silicon host, macOS 27.0.1 (26A434), Apple Swift 6.3.3.
- Strict Release build with complete concurrency checking and warnings as errors:
  passed for arm64 and x86_64. Intel was cross-compiled on the Apple Silicon host.
- Release `FuwaLogicTests`: passed.
- Native `swift test`, with the same strict compiler flags: suite passed,
  67 declared tests in 14 suites. 64 ran; the two explicit recording fixtures and
  existing virtual-display fixture were disabled by default.
- `python3 scripts/test-macos-only.py`: all six checks passed.
- `git diff --check`: passed.
- Universal task-local package: arm64/x86_64 binary, designated requirement,
  embedded-framework loading and icon master/Retina checks passed. The signing
  certificate is the existing Fuwa identity, not a new permission identity.
- Final strict suite with recording fixtures enabled also passed: 66 active
  tests; only the unrelated virtual-display fixture stayed disabled.

The regression tests cover independent hotkey storage and physical-chord
comparison, registration failure/rollback presentation, frame-rate preferences,
application/global visibility composition, newer hide intent during an older
restore, invalidation on clear, crop geometry and Retina sizing, meaningful
picture-change detection, retained paused pixels and seven-language layouts.
They also exercise the existing native termination, Dock and menu behavior.

## Recording fixtures

Ran separately with an existing recording grant:

```sh
FUWA_REFERENCE_CAPTURE_QA=1 FUWA_LIVE_REFERENCE_OUTPUT=/tmp/fuwa-live-reference \
  swift test --filter LiveReferenceWorkflowTests \
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

Both tests passed. Only generated fixture windows were
selected, by exact WindowServer identity and process ID. No user work window was
selected and the tests never requested or reset permission.

- A generated 640 × 320 point picture contains a black left half, a gray upper
  right quadrant and a white lower right quadrant. The real selection view's
  down/drag/up event handlers select a lower-right quarter. ScreenCaptureKit
  returns the expected 320 × 160 pixel white crop from the original 1280 × 640
  Retina image, proving both source coordinates and scaling.
- After committing a crop, stale pixels cannot be cropped or manually paused.
  Switching between equal-sized white and black regions returns the expected
  pixels from a fresh stream generation. Hiding during that replacement and
  restoring returns the requested region without leaking the old stream.
- Moving the native reference panel and then moving its source leaves the
  reference position independent. The fixture uses native frame setters rather
  than a physical mouse drag.
- Hiding removes the panel and its stream. Restoring delivers changed fixture
  pixels. Static content reaches the 1 fps configuration; changed pixels clear
  inactivity and restore the selected 15 fps configuration. This checks policy
  and configuration, without making a measured CPU, power or delivered-fps claim.
- Manual pause survives hide/show with byte-identical pixels and no live stream;
  explicit resume returns fresh pixels. Teardown clears retained pixels.
- A separate generated black/white child process is captured, hidden and then
  terminated. Restore reports the exact source as disappeared, keeps the last
  frame in `sourceClosed`, and unpin clears it. Merely closing a retained AppKit
  window was unsuitable for this check because WindowServer can retain its ID.
  The final variant requests a crop immediately before hiding and destroying
  the child; failed restore retains the full picture and its full-picture
  coordinates, instead of labeling those pixels with the unapplied crop.

## Packaged native application

Launched `dist/Fuwa.app` from this worktree and verified its running bundle path.
Used two task-local AppKit applications with generated content and distinct
bundle IDs (`app.yuxino.fuwa.qafixture`, `app.yuxino.fuwa.qaeditor`). The installed
`/Applications/Fuwa.app` binary digest remained unchanged. After quitting the
three task applications, the original Fuwa preference dictionary was restored
and compared exactly; recording grants were neither requested nor reset.

Native UI automation verified selection of the exact fixture window, live
pin status, switching to independent reference mode, opening/closing controls,
all three option groups, opening the crop chooser and cancelling with Escape,
pause → hide → show retaining pause, explicit resume, application-rule selection,
15 fps selection, and a new pin from the same source inheriting 15 fps.

Actual workspace activation and WindowServer on-screen observations also verified
the selected-app/all-Spaces combination: activating the working fixture's
full-screen Space showed the reference (window 2365, floating layer 3); activating
the source fixture's separate full-screen Space removed every Fuwa window from
the on-screen list. The working fixture's content window occupied 1512 × 949
points. Reading Fuwa controls then continued to report the expected app rule and
hidden status. These are two generated apps, not acceptance across third-party
applications or every Space configuration.

The computer-use interface sends input directly to the selected native window.
Its pin-key attempts did not exercise the Carbon global shortcut, and dragging
the source targeted its own view rather than the floating panel. The crop chooser
also excludes its picture from screen capture. Consequently physical global
chords, reference dragging/resizing and pointer-driven packaged-app cropping
remain separate acceptance limits; the real stream/selection-handler and
geometry regressions above provide their automated coverage.

## Visual review

Rendered the existing app views with fixture data in English, Simplified and
Traditional Chinese, Japanese, Korean, French and German, including compact
layouts, long titles, large text, hidden pins and reference options. Inspected
English/Chinese/Japanese main views and English/Chinese/German reference controls.
The controls now keep picture/visibility/performance navigation and playback
outside the scrollable option group. Inspected the compact German performance
page, Japanese visibility page and Chinese fresh-frame waiting state. Long
navigation labels no longer compete with a redundant form label.
The constrained controls remain scrollable and the restore action stays visible.
Screenshots use fixture titles and version text, not a released application.

Representative evidence is kept in
[`2026-10-10-floating-reference/`](2026-10-10-floating-reference/):

- [Hidden pins and restore](2026-10-10-floating-reference/english-pins-hidden.png)
- [Reference controls](2026-10-10-floating-reference/english-reference-controls.png)
- [Separate visibility shortcut](2026-10-10-floating-reference/simplifiedChinese-settings-main.png)
- [Compact German controls](2026-10-10-floating-reference/german-reference-controls-small.png)
- [Chinese picture options](2026-10-10-floating-reference/simplifiedChinese-reference-controls.png)
- [Japanese visibility options](2026-10-10-floating-reference/japanese-reference-controls-visibility.png)
- [Compact German performance options](2026-10-10-floating-reference/german-reference-controls-performance-small.png)
- [Waiting for fresh pixels](2026-10-10-floating-reference/simplifiedChinese-reference-controls-restoring.png)
- [Generated full picture](2026-10-10-floating-reference/full-generated-window.png)
- [Actual cropped picture](2026-10-10-floating-reference/cropped-generated-window.png)

## Remaining acceptance limits

- Physical mouse dragging/resizing, hardware hotkey presses and the complete
  installed-app workflow are not recorded as end-to-end acceptance here.
  Escape cancellation passed through native UI automation.
- Application activation and all-Spaces full-screen presentation passed the
  generated-app check above. Current-Space anchoring, ordinary desktop Space
  switching, third-party full-screen apps and Stage Manager need interactive checks.
  Space membership uses public AppKit behavior; an off-Space picture may continue
  capturing. Only global/application suppression stops its stream.
- Intel hardware, macOS 14 runtime behavior, external display removal,
  long-running sessions and updater installation remain unverified.
- Inactivity is a sparse picture heuristic. It may miss small unsampled changes
  and cannot establish application completion, errors or input requirements.

## Regressions repaired during integration

Kept source identity and playback intent separate from presentation suppression;
hid all panels before asynchronous shutdown; invalidated older restores; awaited
in-flight stream startup before teardown; retained the last picture on failed
restoration; explicitly cleared the crop selector's image and backing surface
when closing rather than relying on AppKit deallocation; kept crop metadata
truthful while paused/hidden; snapped only
machine-rounding noise in crop pixel dimensions; and persisted fps only on an
explicit fps change. These repairs are covered by the relevant regression and
recording checks above.

The usability pass also covers thin/tall crops with a usable outer window,
resize shrink/grow and subsequent tracking stability, passive inactivity labels,
reference context menus, crop cancellation on configuration changes, selector
focus reuse, friendly names for exited applications, and new-pin visibility
intent even when capture startup fails. A later hide action wins over an older
asynchronous pin resolution.
