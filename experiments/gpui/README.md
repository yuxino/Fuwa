# Fuwa GPUI experiment

This directory is an isolated feasibility prototype. It does **not** replace the
shipping Swift/AppKit application.

## Goal

Prove Fuwa's difficult path before considering a migration:

1. create a GPUI-managed macOS window;
2. reproduce Fuwa's floating, non-activating, click-through mirror behavior;
3. feed a single-window ScreenCaptureKit `CVPixelBuffer` into GPUI's macOS
   surface renderer;
4. verify live/frozen transitions, multi-display scaling, source close, and
   privacy teardown.

The existing Swift implementation remains the reference for behavior.

## Why prototype first

Fuwa currently relies on AppKit `NSPanel`, ScreenCaptureKit,
`AVSampleBufferDisplayLayer`, Accessibility, and explicit privacy-sensitive
teardown. GPUI can render macOS `CVPixelBuffer` surfaces, but that alone does
not prove that Fuwa's complete window behavior can be reproduced safely.

## Exit criteria

Continue the migration only if the prototype can demonstrate:

- a selected source window mirrors at interactive frame rates;
- the mirror stays above normal application windows without stealing focus;
- mouse input passes through the mirror;
- moving/resizing across displays remains aligned;
- freeze/resume and source-window disappearance preserve current semantics;
- screen-recording permission revocation and termination clear retained pixels;
- CPU/GPU/memory are not materially worse than the current implementation.

## Scope

This first commit intentionally contains only the Rust dependency boundary and
the validation plan. Native capture/window adapters will be added here without
changing `Sources/Fuwa` until the hard path has been proven.

## Run

From this directory:

```sh
cargo check
```

The dependency versions are pinned so GPUI snapshot changes do not silently
change the experiment underneath us.
