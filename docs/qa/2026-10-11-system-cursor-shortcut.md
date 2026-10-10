# Pin shortcut with the macOS cursor surface

## Reproduction and diagnosis

The user reproduced the failure after clicking another application, returning the pointer to an existing click-through picture, and pressing Option-Command-P. Fuwa pinned the foreground application instead of removing the hovered picture.

A temporary local diagnostic build captured one physical shortcut invocation. AppKit-to-Quartz conversion agreed with the Core Graphics pointer position, and the visible picture's WindowServer ID was present in the pin mapping. The first overlapping surface was window 2, with no application bundle and layer 2147483630. A separate read-only WindowServer query identified its owner as `Window Server`, a 28-by-40 rectangle, and confirmed its layer equals `CGWindowLevelForKey(.cursorWindow)`.

This is the system mouse cursor, not a content window. The shortcut policy now skips exactly the standard cursor layer, preserving ordinary occluders, focused-system-UI boundaries, and front-to-back picture ordering. It does not skip all anonymous windows or all high layers. Temporary diagnostic code and its output path were removed from the delivered application.

## Validation

- The two regressions for the anonymous cursor and a different foreground application failed before the fix and passed afterward. A third case preserves anonymous high-level occluders below the cursor layer.
- All 164 logic checks passed with strict concurrency and warnings treated as errors.
- The default native suite passed: 71 tests in 17 suites.
- The explicit WindowServer shortcut fixture passed with a click-through, unshared, transparent panel at the production floating level. Tests disable animation so a hidden panel's fade-out surface cannot affect the next assertion. Native helpers do not move the pointer or send keys.
- The arm64 development app and its DMG were built, signed, and validated. The app was installed at the existing development path with the same designated signing requirement; the temporary diagnosis string is absent from its binary.
- Physical shortcut acceptance after switching applications is pending. Synthetic app-local key input is not evidence of Carbon global-hotkey delivery.
