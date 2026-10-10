import CoreGraphics
import Foundation
import FuwaCore
import ScreenCaptureKit

enum PinShortcutIntent: Sendable {
    case unpin(UUID)
    case toggle(TargetIntentSnapshot)
}

struct TargetIntentSnapshot: Sendable {
    let descriptor: WindowDescriptor
    let coordinateSpace: DisplayCoordinateSpace
}

struct ResolvedTarget {
    let window: SCWindow
    let descriptor: WindowDescriptor
    let coordinateSpace: DisplayCoordinateSpace
}

enum TargetResolutionError: Error, Equatable, Sendable {
    case inventoryUnavailable(WindowInventoryError)
    case noEligibleIntent
    case screenRecordingPermissionDenied
    case shareableContentUnavailable(message: String)
    case intentDisappeared(windowID: CGWindowID)
    case intentNotShareable(windowID: CGWindowID)
}

extension TargetResolutionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .inventoryUnavailable(let error):
            error.localizedDescription
        case .noEligibleIntent:
            "No eligible front window is visible."
        case .screenRecordingPermissionDenied:
            "Screen Recording permission is required to pin this window."
        case .shareableContentUnavailable(let message):
            "The capturable window list is unavailable: \(message)"
        case .intentDisappeared:
            "The front window closed before Fuwa could start capturing it."
        case .intentNotShareable:
            "The front window is visible but macOS does not allow it to be captured."
        }
    }
}

/// Resolves the user's visual intent in two deliberately separate stages.
///
/// `snapshotIntent` must be called synchronously by the hotkey handler. Only
/// after that immutable intent exists should the caller start an async task and
/// call `resolve`, which confirms the exact WindowServer ID in
/// ScreenCaptureKit. An unavailable intent is always an error; the resolver
/// never selects a window behind it.
@MainActor
final class TargetResolver {
    func snapshotIntent(
        excluding overlayWindowIDs: Set<CGWindowID> = []
    ) throws -> TargetIntentSnapshot {
        try snapshotIntent(in: captureInventory(), excluding: overlayWindowIDs)
    }

    func snapshotShortcutIntent(
        at appKitPoint: CGPoint,
        overlayPinIDs: [CGWindowID: UUID]
    ) throws -> PinShortcutIntent {
        let inventory = try captureInventory()
        let point = inventory.coordinateSpace.quartzFrame(
            fromAppKitFrame: CGRect(origin: appKitPoint, size: .zero)
        ).origin
        if let id = PinShortcutTargetPolicy.pinnedPicture(
            in: inventory.orderedWindows, at: point, overlayPinIDs: overlayPinIDs,
            frontmostProcessID: inventory.frontmostProcessID
        ) {
            return .unpin(id)
        }
        return .toggle(try snapshotIntent(in: inventory, excluding: Set(overlayPinIDs.keys)))
    }

    private func snapshotIntent(
        in inventory: WindowInventory,
        excluding overlayWindowIDs: Set<CGWindowID>
    ) throws -> TargetIntentSnapshot {
        let context = SelectionContext(
            selfProcessID: ProcessInfo.processInfo.processIdentifier,
            frontmostProcessID: inventory.frontmostProcessID,
            displayBounds: inventory.activeDisplayBounds,
            excludedWindowIDs: overlayWindowIDs
        )
        guard let descriptor = SelectionPolicy.intentWindow(
            in: inventory.orderedWindows,
            context: context
        ) else {
            throw TargetResolutionError.noEligibleIntent
        }

        return TargetIntentSnapshot(
            descriptor: descriptor,
            coordinateSpace: inventory.coordinateSpace
        )
    }

    /// Refreshes an existing source by its original identity. This is the
    /// Resume path for a frozen pin: it refreshes bounds and display topology,
    /// but never applies frontmost-window selection or substitutes another ID.
    func snapshotExactWindow(
        matching previousDescriptor: WindowDescriptor
    ) throws -> TargetIntentSnapshot {
        let inventory = try captureInventory()
        guard let currentDescriptor = inventory.descriptor(
            for: previousDescriptor.id,
            ownerPID: previousDescriptor.ownerPID
        ) else {
            throw TargetResolutionError.intentDisappeared(
                windowID: previousDescriptor.id
            )
        }

        return TargetIntentSnapshot(
            descriptor: currentDescriptor,
            coordinateSpace: inventory.coordinateSpace
        )
    }

    func resolveExact(
        matching previousDescriptor: WindowDescriptor
    ) async throws -> ResolvedTarget {
        let intent = try snapshotExactWindow(matching: previousDescriptor)
        return try await resolve(intent)
    }

    func resolve(_ intent: TargetIntentSnapshot) async throws -> ResolvedTarget {
        guard CGPreflightScreenCaptureAccess() else {
            throw TargetResolutionError.screenRecordingPermissionDenied
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                throw TargetResolutionError.screenRecordingPermissionDenied
            }
            throw TargetResolutionError.shareableContentUnavailable(
                message: error.localizedDescription
            )
        }

        let window = SelectionPolicy.confirm(
            intent.descriptor,
            among: content.windows,
            windowID: \SCWindow.windowID
        )
        guard let window else {
            guard WindowInventory.currentDescriptor(
                for: intent.descriptor.id,
                ownerPID: intent.descriptor.ownerPID
            ) != nil else {
                throw TargetResolutionError.intentDisappeared(
                    windowID: intent.descriptor.id
                )
            }
            throw TargetResolutionError.intentNotShareable(
                windowID: intent.descriptor.id
            )
        }
        guard WindowInventory.currentDescriptor(
            for: intent.descriptor.id,
            ownerPID: intent.descriptor.ownerPID
        ) != nil else {
            throw TargetResolutionError.intentDisappeared(
                windowID: intent.descriptor.id
            )
        }

        return ResolvedTarget(
            window: window,
            descriptor: intent.descriptor,
            coordinateSpace: intent.coordinateSpace
        )
    }

    private func captureInventory() throws -> WindowInventory {
        do {
            return try WindowInventory.capture()
        } catch let error as WindowInventoryError {
            throw TargetResolutionError.inventoryUnavailable(error)
        }
    }
}
