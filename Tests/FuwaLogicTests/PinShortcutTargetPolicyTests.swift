import CoreGraphics
import Foundation
import FuwaCore

func runPinShortcutTargetPolicyTests(runner: inout LogicTestRunner) {
    let first = UUID()
    let second = UUID()
    let overlays: [CGWindowID: UUID] = [101: first, 102: second]
    let bounds = CGRect(x: 120, y: 100, width: 400, height: 300)
    let point = CGPoint(x: 200, y: 200)
    func window(_ id: CGWindowID, alpha: Double = 1, bounds: CGRect = bounds,
                bundle: String? = nil) -> WindowDescriptor {
        WindowDescriptor(id: id, ownerPID: 999, ownerBundleIdentifier: bundle, alpha: alpha, bounds: bounds)
    }
    func select(_ windows: [WindowDescriptor], at point: CGPoint = point) -> UUID? {
        PinShortcutTargetPolicy.pinnedPicture(in: windows, at: point, overlayPinIDs: overlays)
    }
    runner.expect(select([window(101), window(201)]) == first,
                  "shortcut targets the visible pinned picture rather than the front app behind it")
    runner.expect(select([window(102), window(101)]) == second,
                  "overlapping pinned pictures use WindowServer front-to-back order")
    runner.expect(select([window(201), window(101)]) == nil,
                  "an ordinary window blocks a pinned picture behind it")
    runner.expect(select([window(301), window(101)]) == nil,
                  "a control panel blocks a pinned picture behind it")
    runner.expect(select([window(101)], at: CGPoint(x: 10, y: 10)) == nil,
                  "the normal front-window shortcut remains available outside a picture")
    runner.expect(select([window(201)]) == nil,
                  "hidden or removed pictures cannot be selected by stale overlay identities")
    runner.expect(select([window(301, bundle: "com.openai.sky.cuaservice"), window(101)]) == first,
                  "a transparent automation pointer is not mistaken for an occluding window")
    runner.expect(select([window(301, bundle: "com.apple.dock"), window(101)]) == first,
                  "transparent full-display Dock helpers do not block a picture")
    runner.expect(select([window(301, bundle: "com.apple.screencaptureui"), window(101)]) == first,
                  "background recording helpers do not block a picture")
    runner.expect(PinShortcutTargetPolicy.pinnedPicture(
        in: [window(301, bundle: "com.apple.screencaptureui"), window(101)],
        at: point, overlayPinIDs: overlays, frontmostProcessID: 999) == nil,
                  "focused system UI preserves the existing no-fallthrough boundary")
    runner.expect(select([window(201, alpha: 0), window(101)]) == first,
                  "fully transparent surfaces do not block the pinned picture")
    runner.expect(select([window(101)], at: CGPoint(x: CGFloat.nan, y: 200)) == nil,
                  "invalid pointer coordinates cannot choose a picture")
    runner.expect(select([window(201, bounds: .null), window(101)]) == first,
                  "invalid window geometry does not block a valid picture")
    let shifted = CGRect(x: -900, y: -500, width: 400, height: 300)
    runner.expect(select([window(101, bounds: shifted)], at: CGPoint(x: -800, y: -400)) == first,
                  "pointer targeting works on displays to the left and above the primary display")
}
