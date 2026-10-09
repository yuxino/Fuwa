# Floating reference workflows

## Scope

Implement all recommended macOS workflows from the research review: reversible
hide/show, independent reference windows and region capture, application/Space
visibility choices, per-application frame rate, idle frame-rate reduction and
an opt-in picture-inactivity indicator. Input forwarding, Accessibility source
return and virtual-display relocation remain outside this PR, as confirmed by
the user.

## Architecture

`PinOptions` holds UI-independent per-pin configuration. `PinSession` owns capture,
normalized source crop, native reference geometry and picture activity. Its
visibility suspension is orthogonal to the logical playback state. It hides
image and controls synchronously before asynchronous stream shutdown. Returning
to visibility resolves the original source again and waits for fresh pixels.

`PinCoordinator` composes global hide and a selected foreground application's
visibility rule, serializes updates, and rejects stale restoration after clear
or privacy teardown. Native AppKit window membership implements the current
Space choice without private Space identifiers. Fuwa's management-window
activation retains the last external foreground-app context.

`AppModel` exposes actions and observable state to the menu, main list and pin
controls. A second Carbon hotkey has a distinct identifier and configurable
chord, with rollback on registration failure. The settings store remembers the
hide/show shortcut and each source application's selected frame rate.

## User behavior

- Defaults keep the existing source-following, click-through presentation.
- Reference mode can move and resize independently. A drag selection on the
  captured picture chooses a normalized source region; reset restores the whole
  source. It does not move or send input to the source window.
- Hide/show preserves pins, options and live/manual pause intent. Explicitly
  adding a new pin reveals the group. Application conditions still apply.
- Current-Space and all-Spaces choices use native window collection behavior.
- Idle means the sampled picture stopped changing. It does not mean the source
  task completed successfully. Reminders are per-pin and opt-in, in-app only.
- Lock, sleep, session switch, recording revocation and termination retain the
  existing clear-and-re-pin privacy contract.
- All seven UI languages use the same neutral existing design and discoverable
  controls. Extra explanations stay in nearby help affordances.

## Verification

Test geometry normalization and crop composition, pixel activity and throttling,
global/app visibility composition, asynchronous restoration cancellation,
shortcut/settings persistence and rollback, translated actions and constrained
layouts. Run strict release build, logic tests and native lifecycle tests.
Record separately which actual ScreenCaptureKit, Spaces, fullscreen, physical
display and long-session scenarios were exercised. Preserve existing acceptance
evidence and do not infer native behavior from flags alone.
