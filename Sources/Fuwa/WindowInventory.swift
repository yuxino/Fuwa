import AppKit
import CoreGraphics
import FuwaCore

enum WindowInventoryError: Error, Equatable, Sendable {
    case windowListUnavailable
    case activeDisplayListUnavailable
    case noActiveDisplays
    case invalidDisplayCoordinateSpace(DisplayCoordinateSpace.ValidationError)
}

extension WindowInventoryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .windowListUnavailable:
            "Fuwa could not read the current WindowServer window list."
        case .activeDisplayListUnavailable:
            "Fuwa could not read the active display arrangement."
        case .noActiveDisplays:
            "Fuwa could not find an active display."
        case .invalidDisplayCoordinateSpace:
            "The active display arrangement could not be converted safely."
        }
    }
}

/// A synchronous, front-to-back WindowServer snapshot captured for one hotkey
/// invocation. No ScreenCaptureKit availability filtering happens here.
struct WindowInventory: Sendable {
    /// The visual inventory used for target selection. WindowServer preserves
    /// front-to-back order for this on-screen-only list.
    let orderedWindows: [WindowDescriptor]
    let coordinateSpace: DisplayCoordinateSpace
    let frontmostProcessID: pid_t?

    /// Exact WindowServer identities from `.optionAll`. This deliberately
    /// includes minimized windows and windows on another Space: visibility is
    /// not the same thing as source liveness.
    private let allWindowsByID: [CGWindowID: WindowDescriptor]

    var activeDisplayBounds: [CGRect] {
        coordinateSpace.activeDisplayBounds
    }

    /// Returns an exact source descriptor irrespective of whether the source
    /// is currently visible. Callers use this for liveness and geometry
    /// reconciliation, never for choosing a new target.
    func descriptor(for windowID: CGWindowID) -> WindowDescriptor? {
        allWindowsByID[windowID]
    }

    /// PID-qualified identity protects long-running pins from the unlikely
    /// case where WindowServer recycles a closed window's numeric ID.
    func descriptor(
        for windowID: CGWindowID,
        ownerPID: pid_t
    ) -> WindowDescriptor? {
        guard let descriptor = allWindowsByID[windowID],
              descriptor.ownerPID == ownerPID else {
            return nil
        }
        return descriptor
    }

    /// Captures visual intent before any asynchronous ScreenCaptureKit work can
    /// allow z-order or a transient Quick Look window to change.
    @MainActor
    static func capture() throws -> WindowInventory {
        guard let onScreenWindowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            throw WindowInventoryError.windowListUnavailable
        }
        guard let allWindowInfo = CGWindowListCopyWindowInfo(
            .optionAll,
            kCGNullWindowID
        ) as? [[String: Any]] else {
            throw WindowInventoryError.windowListUnavailable
        }

        let displays = try activeDisplayCoordinateSpace()
        let onScreenDescriptors = descriptors(from: onScreenWindowInfo)
        let allDescriptors = descriptors(from: allWindowInfo)
        let frontmostProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        return WindowInventory(
            orderedWindows: onScreenDescriptors,
            coordinateSpace: displays,
            frontmostProcessID: frontmostProcessID,
            allWindowsByID: Dictionary(
                allDescriptors.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    /// Captures only the WindowServer state required to reconcile existing pins.
    /// `.optionAll` is essential here: minimized, off-Space, and other Stage
    /// Manager application-set windows must remain live tracking candidates.
    @MainActor
    static func captureTrackingSnapshot() throws -> WindowTrackingSnapshot {
        guard let allWindowInfo = CGWindowListCopyWindowInfo(
            .optionAll,
            kCGNullWindowID
        ) as? [[String: Any]] else {
            throw WindowInventoryError.windowListUnavailable
        }

        return WindowTrackingSnapshot(
            descriptors: descriptors(
                from: allWindowInfo,
                resolvesBundleIdentifiers: false
            ),
            coordinateSpace: try activeDisplayCoordinateSpace()
        )
    }

    /// A narrow liveness check used only to classify an exact-ID confirmation
    /// failure. It never participates in selecting a replacement target.
    @MainActor
    static func currentDescriptor(for windowID: CGWindowID) -> WindowDescriptor? {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            .optionAll,
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        // Resolve application metadata only for the requested window. Parsing
        // every descriptor here needlessly looks up every running owner on each
        // liveness check and Resume operation.
        guard let matchingInfo = windowInfo.first(where: {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
        }) else { return nil }
        return descriptors(from: [matchingInfo]).first
    }

    /// Exact-ID/PID variant for code that already holds a stable source
    /// identity. Like `capture`, this checks all WindowServer windows rather
    /// than treating off-Space or minimized sources as closed.
    @MainActor
    static func currentDescriptor(
        for windowID: CGWindowID,
        ownerPID: pid_t
    ) -> WindowDescriptor? {
        guard let descriptor = currentDescriptor(for: windowID),
              descriptor.ownerPID == ownerPID else {
            return nil
        }
        return descriptor
    }

    @MainActor
    private static func descriptors(
        from windowInfo: [[String: Any]],
        resolvesBundleIdentifiers: Bool = true
    ) -> [WindowDescriptor] {
        var bundleIdentifiers: [pid_t: String] = [:]
        var resolvedProcessIDs = Set<pid_t>()
        var result: [WindowDescriptor] = []
        result.reserveCapacity(windowInfo.count)

        for info in windowInfo {
            guard let rawDescriptor = RawWindowDescriptor(windowInfo: info) else {
                continue
            }

            let processID = rawDescriptor.ownerPID
            if resolvesBundleIdentifiers,
               resolvedProcessIDs.insert(processID).inserted,
               let bundleIdentifier = NSRunningApplication(
                   processIdentifier: processID
               )?.bundleIdentifier,
               !bundleIdentifier.isEmpty {
                bundleIdentifiers[processID] = bundleIdentifier
            }

            result.append(
                WindowDescriptor(
                    id: rawDescriptor.id,
                    ownerPID: processID,
                    ownerName: rawDescriptor.ownerName,
                    ownerBundleIdentifier: bundleIdentifiers[processID],
                    layer: rawDescriptor.layer,
                    alpha: rawDescriptor.alpha,
                    bounds: rawDescriptor.bounds
                )
            )
        }

        return result
    }

    private static func activeDisplayCoordinateSpace() throws -> DisplayCoordinateSpace {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success else {
            throw WindowInventoryError.activeDisplayListUnavailable
        }
        guard displayCount > 0 else {
            throw WindowInventoryError.noActiveDisplays
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        var capturedDisplayCount: UInt32 = 0
        let displayListError = displayIDs.withUnsafeMutableBufferPointer { buffer in
            CGGetActiveDisplayList(displayCount, buffer.baseAddress, &capturedDisplayCount)
        }
        guard displayListError == .success else {
            throw WindowInventoryError.activeDisplayListUnavailable
        }

        guard capturedDisplayCount <= displayCount else {
            throw WindowInventoryError.activeDisplayListUnavailable
        }
        displayIDs.removeSubrange(Int(capturedDisplayCount)..<displayIDs.count)
        guard !displayIDs.isEmpty else {
            throw WindowInventoryError.noActiveDisplays
        }

        let primaryDisplayBounds = CGDisplayBounds(CGMainDisplayID())
        let activeDisplayBounds = displayIDs.map(CGDisplayBounds)

        do {
            return try DisplayCoordinateSpace(
                primaryDisplayBounds: primaryDisplayBounds,
                activeDisplayBounds: activeDisplayBounds
            )
        } catch let error as DisplayCoordinateSpace.ValidationError {
            throw WindowInventoryError.invalidDisplayCoordinateSpace(error)
        }
    }
}

private struct RawWindowDescriptor {
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String?
    let layer: Int
    let alpha: Double
    let bounds: CGRect

    init?(windowInfo: [String: Any]) {
        guard
            let windowNumber = windowInfo[kCGWindowNumber as String] as? NSNumber,
            let processIdentifier = windowInfo[kCGWindowOwnerPID as String] as? NSNumber,
            let boundsDictionary = windowInfo[kCGWindowBounds as String] as? [String: Any],
            let x = (boundsDictionary["X"] as? NSNumber)?.doubleValue,
            let y = (boundsDictionary["Y"] as? NSNumber)?.doubleValue,
            let width = (boundsDictionary["Width"] as? NSNumber)?.doubleValue,
            let height = (boundsDictionary["Height"] as? NSNumber)?.doubleValue
        else {
            return nil
        }

        id = windowNumber.uint32Value
        ownerPID = pid_t(processIdentifier.int32Value)
        ownerName = windowInfo[kCGWindowOwnerName as String] as? String
        layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        alpha = (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        bounds = CGRect(x: x, y: y, width: width, height: height)
    }
}
