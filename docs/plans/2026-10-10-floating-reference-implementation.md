# Floating Reference Implementation Plan

**Goal:** Make Fuwa references easy to place, crop, hide, restore and observe while
the user works in another Mac application.

**Architecture:** One shared feature worktree, with disjoint file ownership and
one integration owner. Capture sessions retain lifecycle ownership; visibility
rules compose in the coordinator; UI uses shared `PinOptions` and model actions.

**Tech Stack:** Swift 6, AppKit, SwiftUI, ScreenCaptureKit, Carbon hotkeys,
Swift Testing and the existing executable logic-test harness.

---

The user requested parallel execution in this conversation. The implementation
is integrated into `feat/floating-reference-workflows` and delivered as one PR.

### Task 1: Shared options and integration contract

- Create `Sources/FuwaCore/PinOptions.swift` with source-following/reference,
  normalized crop, app/Space visibility, fps, idle reduction and reminder options.
- Add actions and observable state to `Sources/Fuwa/AppModel.swift`.
- Preserve defaults and existing call sites; expose new snapshot fields with
  default values.

### Task 2: Capture and native reference presentation (parallel)

- Modify `Sources/Fuwa/PinSession.swift` and `Sources/Fuwa/CaptureView.swift`;
  create reference/crop presentation and core geometry/activity policy files.
- Implement movable, resizable reference mode, capture-side region configuration,
  actual bounded pixel-change sampling and inactivity timer.
- Suspend hidden capture without losing logical playback intent; guard restore
  by lifecycle revision and source identity.
- Add focused crop/activity and native lifecycle tests in uniquely named files.

### Task 3: Visibility coordinator (parallel)

- Modify `Sources/Fuwa/PinCoordinator.swift`; create visibility policy helpers.
- Compose global/app visibility, preserve last external foreground application,
  reveal on explicit new pin, reset on clear and cancel obsolete asynchronous
  visibility reconciliation.
- Coordinate native Space membership with Task 2 using public AppKit APIs.
- Add policy/race tests and hooks for per-source-app frame-rate defaults.

### Task 4: Controls and localization (parallel)

- Modify pin controls, native status menu, main pins view, settings and shared
  shortcut recorder; add compact reusable workflow controls.
- Expose modes, crop/reset, app/Space rules, fps and idle options with necessary
  labels visible and additional help on demand.
- Translate all new strings in the seven existing languages; add action and
  offscreen-layout tests for hidden pins, long labels and constrained widths.

### Task 5: Settings and hotkeys (integration owner)

- Modify `Sources/Fuwa/AppSettings.swift`, `GlobalHotKey.swift`, `AppDelegate.swift`
  and `Sources/FuwaCore/KeyboardShortcut.swift`.
- Distinct Carbon identifier for hide/show; physical-chord conflict checking and
  rollback; persist only successfully registered preferences.
- Persist source-app frame rates and wire coordinator/model callbacks.
- Add settings/model tests covering failure, inactive registration and independent
  preference storage.

### Task 6: Verification and PR

Run after integration:

```sh
swift build --configuration release --product Fuwa -Xswiftc -Osize -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swift run --configuration release -Xswiftc -Osize -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors FuwaLogicTests
FUWA_HEADLESS_TESTS=1 swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

Perform a separate defect-and-claim review, fix supported regressions, inspect
final diff and run relevant checks again only after changes. Update user-facing
docs and bilingual unreleased notes. Record native evidence and remaining
acceptance limits. Commit only task files, push the feature branch, create and
attach one PR, inspect CI. A major PR is not merged to main without the user's
decision. No release, tag or installed production-app replacement is implied.
