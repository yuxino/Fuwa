# Floating reference verification — 2026-10-10

Scope: macOS reference placement, picture cropping, temporary visibility,
application/Space rules, frame-rate preferences and picture inactivity. Input
forwarding, exact source-window activation and virtual displays are deferred.
This record covers a development branch; no version, release, app installation,
signature or recording-permission change was made.

## Environment and automated checks

- Apple Silicon host, macOS 27.0.1 (26A434), Apple Swift 6.3.3.
- Strict Release build with complete concurrency checking and warnings as errors:
  passed for arm64 and x86_64. Intel was cross-compiled on the Apple Silicon host.
- Release `FuwaLogicTests`: passed.
- Native `swift test`, with the same strict compiler flags: suite passed,
  57 declared tests in 14 suites. 54 ran; the two explicit recording fixtures and
  existing virtual-display fixture were disabled by default.
- `python3 scripts/test-macos-only.py`: all six checks passed.
- `git diff --check`: passed.

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

Both tests passed (18.944 seconds combined). Only generated fixture windows were
selected, by exact WindowServer identity and process ID. No user work window was
selected and the tests never requested or reset permission.

- A generated 640 × 320 point picture contains a black left half, a gray upper
  right quadrant and a white lower right quadrant. The real selection view's
  down/drag/up event handlers select a lower-right quarter. ScreenCaptureKit
  returns the expected 320 × 160 pixel white crop from the original 1280 × 640
  Retina image, proving both source coordinates and scaling.
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

## Visual review

Rendered the existing app views with fixture data in English, Simplified and
Traditional Chinese, Japanese, Korean, French and German, including compact
layouts, long titles, large text, hidden pins and reference options. Inspected
English/Chinese/Japanese main views and English/Chinese/German reference controls.
The constrained controls remain scrollable and the restore action stays visible.
Screenshots use fixture titles and version text, not a released application.

Representative evidence is kept in
[`2026-10-10-floating-reference/`](2026-10-10-floating-reference/):

- [Hidden pins and restore](2026-10-10-floating-reference/english-pins-hidden.png)
- [Reference controls](2026-10-10-floating-reference/english-reference-controls.png)
- [Separate visibility shortcut](2026-10-10-floating-reference/simplifiedChinese-settings-main.png)
- [Compact German controls](2026-10-10-floating-reference/german-reference-controls-small.png)
- [Generated full picture](2026-10-10-floating-reference/full-generated-window.png)
- [Actual cropped picture](2026-10-10-floating-reference/cropped-generated-window.png)

## Remaining acceptance limits

- Physical mouse dragging/resizing, hardware hotkey presses, crop cancellation
  via a physical Escape key and the complete installed-app workflow are not
  recorded as end-to-end acceptance here.
- Application activation rules have policy/race coverage. Real app switching,
  current/all Spaces, full-screen apps and Stage Manager need interactive checks.
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
restoration; kept crop metadata truthful while paused/hidden; snapped only
machine-rounding noise in crop pixel dimensions; and persisted fps only on an
explicit fps change. These repairs are covered by the relevant regression and
recording checks above.
