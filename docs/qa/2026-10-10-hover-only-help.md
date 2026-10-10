# Hover-only help verification

The shared help icon is a neutral, noneditable native image. AppKit owns its hover tooltip; the click popover and floating-panel focus exceptions have been removed. Existing localized explanations and accessibility label/help remain intact.

## Checks

- macOS 27.0.1, Apple Silicon.
- Strict native `swift test` passed: 69 tests in 15 suites. Capture and virtual-display probes were not explicitly enabled.
- Strict Release build with `-Osize`, complete concurrency checking and warnings as errors passed. Release `FuwaLogicTests` passed.
- The existing help regression test now verifies tooltip registration, neutral tint, image accessibility role, updated copy, no target/action, no first-responder acceptance and no accessibility press action.
- A disposable native SwiftUI window hosted the exact production `FuwaHelpIcon`. Native UI automation confirmed its gray appearance and image/help accessibility text. After focusing a text field and clicking the image, the field remained focused, the icon stayed gray and no explanation popover opened.
- The automation interface has no pointer-move/hover operation. It did not observe an expanded native tooltip, so tooltip registration is the evidence for hover help; physical pointer-dwell acceptance is not claimed.
- The standalone fixture was compiled with an explicit macOS 14 target because this toolchain's default standalone target exceeds the running OS. The Swift package already declares macOS 14.

The running development application and installed application were not replaced or restarted. This pass does not publish a release or change capture, permissions, updater metadata or localized copy.
