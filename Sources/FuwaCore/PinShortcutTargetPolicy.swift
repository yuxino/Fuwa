import CoreGraphics
import Foundation

/// Select only the foremost visible surface under the pointer. Ordinary windows
/// and Fuwa controls block pictures behind them, even if those pictures are pins.
public enum PinShortcutTargetPolicy {
    public static func pinnedPicture(
        in orderedWindows: [WindowDescriptor],
        at point: CGPoint,
        overlayPinIDs: [CGWindowID: UUID],
        frontmostProcessID: pid_t? = nil
    ) -> UUID? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let systemUI = SelectionContext.defaultSystemUIBundleIdentifiers
        func isSystemUI(_ window: WindowDescriptor) -> Bool {
            guard let bundle = window.ownerBundleIdentifier?.lowercased() else { return false }
            return systemUI.contains(bundle)
        }
        // Preserve source-selection's active-system-UI boundary. Otherwise,
        // full-display transparent Dock, recording and cursor helpers must not
        // obscure real pictures just because their WindowServer bounds overlap.
        if let frontmostProcessID,
           orderedWindows.contains(where: { $0.ownerPID == frontmostProcessID && isSystemUI($0) }) {
            return nil
        }
        for window in orderedWindows {
            if isSystemUI(window) { continue }
            let bounds = window.bounds
            guard window.alpha.isFinite, window.alpha > 0.01,
                  bounds.minX.isFinite, bounds.minY.isFinite,
                  bounds.width.isFinite, bounds.height.isFinite,
                  bounds.width > 0, bounds.height > 0,
                  bounds.contains(point) else { continue }
            return overlayPinIDs[window.id]
        }
        return nil
    }
}
