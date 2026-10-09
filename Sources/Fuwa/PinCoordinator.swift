import AppKit
import CoreGraphics
import Foundation
import FuwaCore

enum PinCoordinatorError: LocalizedError {
    case pinNotFound
    case operationCancelled
    case pinLimitReached(maximum: Int)
    case screenRecordingRevoked

    var errorDescription: String? {
        switch self {
        case .pinNotFound:
            "This pin is no longer available."
        case .operationCancelled:
            "The pin operation was cancelled."
        case .pinLimitReached(let maximum):
            "Fuwa keeps up to \(maximum) windows pinned at once. Unpin one before adding another."
        case .screenRecordingRevoked:
            "Screen Recording permission was removed. Fuwa cleared every captured frame."
        }
    }
}

@MainActor
final class PinCoordinator {
    static let maximumPinCount = 8

    weak var presentationModel: AppModel?
    var onPinsChanged: (([PinSnapshot]) -> Void)?
    var onFailure: ((Error) -> Void)?

    private let resolver = TargetResolver()
    private var displayObserver: NSObjectProtocol?
    private let tracker: WindowTracker
    private var sessionsByID: [UUID: PinSession] = [:]
    private var sessionIDByWindowID: [CGWindowID: UUID] = [:]
    private var insertionOrder: [UUID] = []
    private var pendingPinRequests = PendingPinRequests()
    private var pendingSessionOperations = Set<UUID>()
    private var operationGeneration: UInt64 = 0

    init() {
        tracker = WindowTracker()
        tracker.onInventory = { [weak self] inventory in
            self?.reconcileSessions(with: inventory)
        }
        tracker.onError = { [weak self] error in
            self?.onFailure?(error)
        }
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for session in self.sessionsByID.values {
                    session.reconcileDisplayArrangement()
                }
            }
        }
    }

    isolated deinit {
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
    }

    var snapshots: [PinSnapshot] {
        insertionOrder.reversed().compactMap { sessionsByID[$0]?.snapshot }
    }

    var pinCount: Int {
        sessionsByID.count
    }

    func setCaptureQuality(_ quality: CaptureQuality, for id: UUID) {
        sessionsByID[id]?.setCaptureQuality(quality)
    }

    func focusControls(_ id: UUID) {
        sessionsByID[id]?.focusControls()
    }

    func snapshotFrontmostIntent() throws -> TargetIntentSnapshot {
        try resolver.snapshotIntent(excluding: overlayWindowIDs)
    }

    func toggle(_ intent: TargetIntentSnapshot) async throws {
        if let sessionID = sessionIDByWindowID[intent.descriptor.id] {
            await unpin(sessionID)
            return
        }

        let requestToken: UUID
        switch pendingPinRequests.reserve(
            windowID: intent.descriptor.id,
            activeWindowIDs: Set(sessionIDByWindowID.keys),
            maximumCount: Self.maximumPinCount
        ) {
        case .reserved(let token):
            requestToken = token
        case .duplicate:
            return
        case .limitReached:
            throw PinCoordinatorError.pinLimitReached(maximum: Self.maximumPinCount)
        }

        let requestedGeneration = operationGeneration
        defer {
            pendingPinRequests.finish(windowID: intent.descriptor.id, token: requestToken)
        }

        let target = try await resolver.resolve(intent)
        guard requestedGeneration == operationGeneration else {
            throw PinCoordinatorError.operationCancelled
        }

        if let duplicateSessionID = sessionIDByWindowID[target.descriptor.id] {
            await unpin(duplicateSessionID)
            return
        }

        let session = PinSession(target: target)
        session.presentationModel = presentationModel
        configureCallbacks(for: session)
        sessionsByID[session.id] = session
        sessionIDByWindowID[session.sourceWindowID] = session.id
        insertionOrder.append(session.id)
        publishSnapshots()

        do {
            try await session.startInitialCapture(with: target)
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                clearAllImmediately()
                throw TargetResolutionError.screenRecordingPermissionDenied
            }
            await removeFailedSession(session)
            throw error
        }
        updateTrackerActivity()
        publishSnapshots()
    }

    func freeze(_ id: UUID) async throws {
        guard let session = sessionsByID[id] else {
            throw PinCoordinatorError.pinNotFound
        }
        guard pendingSessionOperations.insert(id).inserted else { return }
        defer { pendingSessionOperations.remove(id) }
        try await session.freeze(reason: .manual)
        updateTrackerActivity()
        publishSnapshots()
    }

    func resume(_ id: UUID) async throws {
        guard let session = sessionsByID[id] else {
            throw PinCoordinatorError.pinNotFound
        }
        guard pendingSessionOperations.insert(id).inserted else { return }
        defer { pendingSessionOperations.remove(id) }

        do {
            let target = try await resolver.resolveExact(matching: session.descriptor)
            guard sessionsByID[id] === session else {
                throw PinCoordinatorError.operationCancelled
            }
            try await session.resume(with: target)
        } catch TargetResolutionError.screenRecordingPermissionDenied {
            // Resuming can be the first operation after permission was revoked
            // while every pin was frozen. Treat that detection as the same
            // global privacy boundary as an active stream ending.
            clearAllImmediately()
            throw TargetResolutionError.screenRecordingPermissionDenied
        } catch TargetResolutionError.intentDisappeared {
            guard sessionsByID[id] === session else {
                throw PinCoordinatorError.operationCancelled
            }
            await session.markSourceUnavailable()
            updateTrackerActivity()
            publishSnapshots()
            throw TargetResolutionError.intentDisappeared(windowID: session.sourceWindowID)
        }
        updateTrackerActivity()
        publishSnapshots()
    }

    func unpin(_ id: UUID) async {
        guard let session = sessionsByID.removeValue(forKey: id) else { return }
        pendingSessionOperations.remove(id)
        sessionIDByWindowID.removeValue(forKey: session.sourceWindowID)
        insertionOrder.removeAll(where: { $0 == id })
        session.onChange = nil
        session.onGeometryChanged = nil
        session.onFailure = nil
        session.onScreenRecordingRevoked = nil
        session.prepareForStop()
        updateTrackerActivity()
        publishSnapshots()
        await session.stop()
    }

    func clearAll() async {
        let sessions = prepareToClearAll()
        await finishStopping(sessions)
    }

    /// Used for lock, sleep, user switch, permission revocation and termination.
    /// The sensitive work completes synchronously; stream shutdown continues in
    /// a detached main-actor task after every panel and pixel has disappeared.
    func clearAllImmediately() {
        let sessions = prepareToClearAll()
        Task { @MainActor in
            await finishStopping(sessions)
        }
    }

    private func prepareToClearAll() -> [PinSession] {
        operationGeneration &+= 1
        let sessions = insertionOrder.compactMap { sessionsByID[$0] }
        sessionsByID.removeAll()
        sessionIDByWindowID.removeAll()
        insertionOrder.removeAll()
        pendingPinRequests.clear()
        pendingSessionOperations.removeAll()
        tracker.stop()

        for session in sessions {
            session.onChange = nil
            session.onGeometryChanged = nil
            session.onFailure = nil
            session.onScreenRecordingRevoked = nil
            session.prepareForStop()
        }
        publishSnapshots()

        return sessions
    }

    private func finishStopping(_ sessions: [PinSession]) async {
        for session in sessions {
            await session.stop()
        }
    }

    private var overlayWindowIDs: Set<CGWindowID> {
        Set(sessionsByID.values.compactMap { $0.overlayWindowID })
    }

    private func configureCallbacks(for session: PinSession) {
        session.onChange = { [weak self, weak session] in
            guard let self, let session, self.sessionsByID[session.id] === session else {
                return
            }
            self.updateTrackerActivity()
            self.publishSnapshots()
        }
        session.onGeometryChanged = { [weak self] in
            self?.tracker.markGeometryChanged()
        }
        session.onFailure = { [weak self] error in
            self?.onFailure?(error)
        }
        session.onScreenRecordingRevoked = { [weak self] in
            guard let self else { return }
            self.clearAllImmediately()
            self.onFailure?(PinCoordinatorError.screenRecordingRevoked)
        }
    }

    private func reconcileSessions(with inventory: WindowTrackingSnapshot) {
        for session in sessionsByID.values where session.needsWindowTracking {
            session.reconcile(
                descriptor: inventory.descriptor(for: session.sourceWindowID),
                coordinateSpace: inventory.coordinateSpace
            )
        }
        updateTrackerActivity()
    }

    private func updateTrackerActivity() {
        if sessionsByID.values.contains(where: { $0.needsWindowTracking }) {
            tracker.start()
        } else {
            tracker.stop()
        }
    }

    private func removeFailedSession(_ session: PinSession) async {
        guard sessionsByID[session.id] === session else { return }
        sessionsByID.removeValue(forKey: session.id)
        sessionIDByWindowID.removeValue(forKey: session.sourceWindowID)
        insertionOrder.removeAll(where: { $0 == session.id })
        session.onChange = nil
        session.onGeometryChanged = nil
        session.onFailure = nil
        session.onScreenRecordingRevoked = nil
        session.prepareForStop()
        updateTrackerActivity()
        publishSnapshots()
        await session.stop()
    }

    private func publishSnapshots() {
        onPinsChanged?(snapshots)
    }
}
