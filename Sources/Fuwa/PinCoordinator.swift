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
    var onVisibilityChanged: ((Bool) -> Void)?
    /// Persists an explicitly changed frame-rate preference for this source app.
    var onOptionsChanged: ((PinSnapshot) -> Void)?
    var frameRateForApplication: ((String?) -> PinFrameRate)?

    private let resolver = TargetResolver()
    private var displayObserver: NSObjectProtocol?
    private var applicationObserver: NSObjectProtocol?
    private let tracker: WindowTracker
    private let visibilityReconciler = PinVisibilityReconciler()
    private var visibilityPolicy: PinVisibilityPolicy
    private var sessionsByID: [UUID: PinSession] = [:]
    private var sessionIDByWindowID: [CGWindowID: UUID] = [:]
    private var insertionOrder: [UUID] = []
    private var pendingPinRequests = PendingPinRequests()
    private var pendingSessionOperations = Set<UUID>()
    private var operationGeneration: UInt64 = 0

    init() {
        tracker = WindowTracker()
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        visibilityPolicy = PinVisibilityPolicy(
            activeApplicationBundleIdentifier: frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
                ? nil : frontmostApplication?.bundleIdentifier,
            ownBundleIdentifier: Bundle.main.bundleIdentifier
        )
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
        applicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bundleIdentifier = application.bundleIdentifier
            let processIdentifier = application.processIdentifier
            MainActor.assumeIsolated {
                guard let self,
                      self.visibilityPolicy.applicationActivated(
                        bundleIdentifier: bundleIdentifier,
                        isFuwa: processIdentifier == ProcessInfo.processInfo.processIdentifier
                      ) else { return }
                self.prepareRequiredSuppression()
                self.requestVisibilityUpdate()
            }
        }
    }

    isolated deinit {
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        if let applicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationObserver)
        }
        visibilityReconciler.invalidate()
    }

    var snapshots: [PinSnapshot] {
        insertionOrder.reversed().compactMap { sessionsByID[$0]?.snapshot }
    }

    var pinCount: Int {
        sessionsByID.count
    }

    var arePinsHidden: Bool {
        visibilityPolicy.arePinsHidden
    }

    func togglePinsVisibility() async throws {
        guard !sessionsByID.isEmpty else { return }
        setPinsHidden(!arePinsHidden)
        try await reconcileVisibility()
    }

    func setOptions(_ options: PinOptions, for id: UUID) {
        guard let session = sessionsByID[id] else { return }
        session.setOptions(options)
        requestVisibilityUpdate()
        publishSnapshots()
    }

    func beginCropSelection(_ id: UUID) {
        sessionsByID[id]?.beginCropSelection()
    }

    func setCaptureQuality(_ quality: CaptureQuality, for id: UUID) {
        sessionsByID[id]?.setCaptureQuality(quality)
    }

    func focusControls(_ id: UUID) {
        sessionsByID[id]?.focusControls()
    }

    func refreshPresentationCopy() {
        for session in sessionsByID.values { session.refreshPresentationCopy() }
    }

    func snapshotFrontmostIntent() throws -> TargetIntentSnapshot {
        try resolver.snapshotIntent(excluding: overlayWindowIDs)
    }

    func snapshotShortcutIntent(at point: CGPoint) throws -> PinShortcutIntent {
        var overlayPinIDs: [CGWindowID: UUID] = [:]
        for (id, session) in sessionsByID {
            if let windowID = session.overlayWindowID { overlayPinIDs[windowID] = id }
        }
        return try resolver.snapshotShortcutIntent(at: point, overlayPinIDs: overlayPinIDs)
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
        let requestedVisibilityRevision = visibilityPolicy.globalVisibilityRevision
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
        var options = session.options
        if let frameRate = frameRateForApplication?(session.snapshot.bundleIdentifier) {
            options.frameRate = frameRate
            session.setOptions(options)
        }
        // Adding a new reference is an explicit request to see the group again.
        // Application-specific rules still apply to each existing reference.
        if visibilityPolicy.revealAfterAddingPin(ifUnchangedSince: requestedVisibilityRevision) {
            onVisibilityChanged?(false)
            // Restore the existing group even if this new capture fails to start.
            // Otherwise its visible policy would disagree with retained hidden panels.
            requestVisibilityUpdate()
        }
        session.presentationModel = presentationModel
        configureCallbacks(for: session)
        sessionsByID[session.id] = session
        sessionIDByWindowID[session.sourceWindowID] = session.id
        insertionOrder.append(session.id)
        publishSnapshots()

        do {
            if visibilityPolicy.suppresses(session.options) {
                try await session.setPresentationSuppressed(true)
            }
            try await session.startInitialCapture(with: target)
            guard requestedGeneration == operationGeneration,
                  sessionsByID[session.id] === session else {
                throw PinCoordinatorError.operationCancelled
            }
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
        try await reconcileVisibility()
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
        if sessionsByID.isEmpty { setPinsHidden(false) }
        session.onChange = nil
        session.onGeometryChanged = nil
        session.onFailure = nil
        session.onScreenRecordingRevoked = nil
        session.onOptionsChanged = nil
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
        visibilityReconciler.invalidate()
        let sessions = insertionOrder.compactMap { sessionsByID[$0] }
        sessionsByID.removeAll()
        sessionIDByWindowID.removeAll()
        insertionOrder.removeAll()
        pendingPinRequests.clear()
        pendingSessionOperations.removeAll()
        setPinsHidden(false)
        tracker.stop()

        for session in sessions {
            session.onChange = nil
            session.onGeometryChanged = nil
            session.onFailure = nil
            session.onScreenRecordingRevoked = nil
            session.onOptionsChanged = nil
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
        var previousFrameRate = session.options.frameRate
        session.onOptionsChanged = { [weak self, weak session] options in
            guard let self, let session, self.sessionsByID[session.id] === session else { return }
            if options.frameRate != previousFrameRate {
                previousFrameRate = options.frameRate
                self.onOptionsChanged?(session.snapshot)
            }
            self.prepareRequiredSuppression()
            self.requestVisibilityUpdate()
        }
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
        if sessionsByID.isEmpty { setPinsHidden(false) }
        session.onChange = nil
        session.onGeometryChanged = nil
        session.onFailure = nil
        session.onScreenRecordingRevoked = nil
        session.onOptionsChanged = nil
        session.prepareForStop()
        updateTrackerActivity()
        publishSnapshots()
        await session.stop()
    }

    private func publishSnapshots() {
        onPinsChanged?(snapshots)
    }

    private func setPinsHidden(_ hidden: Bool) {
        guard arePinsHidden != hidden else { return }
        visibilityPolicy.arePinsHidden = hidden
        if hidden { prepareRequiredSuppression() }
        onVisibilityChanged?(hidden)
    }

    private func prepareRequiredSuppression() {
        for id in insertionOrder {
            guard let session = sessionsByID[id],
                  visibilityPolicy.suppresses(session.options),
                  !session.snapshot.isHidden else { continue }
            session.preparePresentationSuppression()
        }
    }

    private func requestVisibilityUpdate() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.reconcileVisibility()
            } catch is CancellationError {
                // Clearing pins intentionally invalidates pending visibility work.
            } catch {
                self.onFailure?(error)
            }
        }
    }

    private func reconcileVisibility() async throws {
        try await visibilityReconciler.reconcile { [weak self] in
            guard let self else { throw CancellationError() }
            let requestedGeneration = self.operationGeneration
            var firstError: Error?
            // Conceal every affected panel before awaiting any stream shutdown.
            // A slow first stream must not leave the remaining references visible.
            self.prepareRequiredSuppression()
            for id in self.insertionOrder {
                try Task.checkCancellation()
                guard requestedGeneration == self.operationGeneration else {
                    throw CancellationError()
                }
                guard let session = self.sessionsByID[id] else { continue }
                let suppressed = self.visibilityPolicy.suppresses(session.options)
                if suppressed || session.snapshot.isHidden != suppressed {
                    do {
                        try await session.setPresentationSuppressed(suppressed)
                    } catch {
                        guard requestedGeneration == self.operationGeneration else {
                            throw CancellationError()
                        }
                        if self.sessionsByID[id] === session, firstError == nil {
                            firstError = error
                        }
                    }
                }
            }
            self.updateTrackerActivity()
            self.publishSnapshots()
            if let firstError { throw firstError }
        }
    }
}
