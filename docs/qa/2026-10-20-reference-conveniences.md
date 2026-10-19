# Reference conveniences and first-use guide

## Research evidence

Reviewed [PipNow's public website](https://pipnow.app/) and its complete
[120-second promotional video](https://pipnow.app/pipnow-promo-v3.mp4).
The player reached 120 seconds / ended. The full timeline was inspected in
chronological order using 61 frames, at two-second intervals through 118 seconds
and the final 119.9-second frame. Observations are visual; audio was muted.

- 16–30 seconds: three entry points, including a window list with thumbnails.
- 32–38: direct source-region selection.
- 40–48: temporary enlarged preview beside a small reference.
- 50–58: a separately retained, interactive preview, then Escape to close.
- 68–78: per-window controls, opacity and full clarity while hovering.
- 80–88: temporary hide gesture and double-click source activation.
- 90–100: corner arrangement and display changes.
- 102–120: permission/privacy presentation and closing download screen.

Also downloaded the official PipNow 1.0.4 (390) trial, verified its notarized
Developer ID signature, and inspected all six onboarding pages in the running
app. The last page showed both Accessibility and Screen Recording ungranted.
Neither grant was added. This confirms onboarding content, not actual capture
or input forwarding. The trial was quit afterward.

Fuwa uses independently written code, wording, tests and a small original
window diagram. No third-party source or product assets were incorporated.
Interactive input forwarding and direct source-region selection are not part
of this change. Fuwa retains its existing shortcut and permission boundaries.

## Implementation and verification

- Adjacent, click-through hover preview reuses the existing capture stream.
  Reference opacity becomes fully clear during hover independently of preview.
- Right-click sizes, source-app activation and optional Control–Option hold to
  hide remain independent of manual hiding, pause state and application rules.
- Picker thumbnails use bounded, memory-only screenshot requests; stale and
  identity-mismatched results are rejected. Native layers clear synchronously
  at privacy boundaries.
- Corner arrangement operates separately on each display. It preserves source
  windows and hidden/paused states. Tests caught and fixed a minimum-size rule
  that otherwise enlarged tightly arranged windows again after tracking/moving.
- Getting Started is available from the sidebar and menu. New users can skip
  it; existing capture setups keep their usual entry view. Permission is only
  requested after an explicit button press, using the existing once-only policy.
- Strict native suite: 124 tests across 28 suites passed. Capture/physical-input
  acceptance is separate from these generated-state tests.
- Offscreen rendering covers all seven languages, default and minimum guide
  windows, reference controls and settings. Actions remain fixed below the
  guide's scrollable content.

## Final package and native acceptance

- Strict Release builds completed for arm64 and x86_64. Release logic tests,
  update metadata/checksum tests, macOS/package/DMG checks and icon verification
  passed. The signed universal app and DMG validated successfully.
- Installed through the project's stable installer at `/Applications/Fuwa.app`.
  Its full designated requirement still uses identifier `app.yuxino.fuwa` and
  certificate root `c45731ee0170184a7542cbb1972420e319ac9d56`. The existing recording
  grant was confirmed inside the installed app; no grant reset was performed.
- Native UI confirmed the old-user list entry, reopening Getting Started,
  granted permission state, and the guide's Choose a Window action.
- Two generated source windows produced distinct, correct thumbnails and live
  captured pictures. Both were converted to independent references. Setting a
  reference to 50% opacity was also confirmed in WindowServer metadata.
- Native controls arranged the references at the top right, paused one picture,
  hid both, arranged them at the bottom left while hidden, and restored them.
  The paused picture stayed paused and the other stayed live. The resulting
  frames had a 12-point gap and stayed inside the visible display.
- Both Fuwa and the generated source app were quit after the check, clearing
  the test references. The installed app is the local development build; no
  release or updater metadata was published.

Computer Use's app-directed input did not move the physical pointer, so it does
not establish real pointer-dwell, right-click/double-click or held global-key
acceptance. Hover geometry/opacity and the temporary-hide state machine are
covered by automated tests, not claimed as physical-input verification. Also
unverified: fresh OS permission approval, Intel hardware, physical multi-display
use and a full updater installation. No privacy permissions were added to the
PipNow trial, so its capture and input-forwarding behavior was not exercised.
