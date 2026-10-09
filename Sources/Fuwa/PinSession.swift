import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import FuwaCore
import ScreenCaptureKit
import SwiftUI

enum PinSessionError: LocalizedError {
    case invalidTransition(PinTransitionError)
    case captureStartFailed(String)
    case captureStartInterrupted
    case captureFailed(String)
    case captureResumeTimedOut
    case freezeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidTransition(let error):
            "Invalid pin state transition: \(error)"
        case .captureStartFailed(let message):
            "Fuwa could not start capturing this window: \(message)"
        case .captureStartInterrupted:
            "The capture stopped while Fuwa was starting it."
        case .captureFailed(let message):
            "Window capture failed: \(message)"
        case .captureResumeTimedOut:
            "Fuwa could not resume live capture. The previous frozen frame is still visible."
        case .freezeFailed(let message):
            "Fuwa could not preserve the last frame: \(message)"
        }
    }
}

struct PinSnapshot: Identifiable, Equatable {
    let id: UUID
    let sourceWindowID: CGWindowID
    let applicationName: String
    let bundleIdentifier: String?
    let windowTitle: String
    let state: PinState
    let errorMessage: String?
    var captureQuality: CaptureQuality = .native
    var options: PinOptions = PinOptions()
    var isHidden = false
    var isIdle = false

    var canAdjustQuality: Bool { state == .live }
    var canChooseArea: Bool { state == .live && !isHidden }

    var canFreeze: Bool {
        state == .live
    }

    var canResume: Bool {
        state == .frozen(.manual) || state == .frozen(.captureInterrupted)
    }

}

@MainActor
final class PinSession {
    private static let firstCompleteFrameTimeout: Duration = .seconds(8)

    let id: UUID

    var onChange: (() -> Void)?
    var onGeometryChanged: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var onScreenRecordingRevoked: (() -> Void)?
    var onOptionsChanged: ((PinOptions) -> Void)?

    private(set) var descriptor: WindowDescriptor
    private(set) var coordinateSpace: DisplayCoordinateSpace

    private var machine = PinStateMachine()
    private var applicationName: String
    private var bundleIdentifier: String?
    private var windowTitle: String
    private var errorMessage: String?

    weak var presentationModel: AppModel?
    private var controlsPanel: NSPanel?
    private var panel: NSPanel?
    private var captureView: CaptureView?
    private var currentCycle: CaptureCycle?
    private var nextGeneration: UInt64 = 0
    private var firstFrameWatchdogTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var teardownTask: Task<Void, Never>?
    private var missingObservationCount = 0
    private var isHandlingMissingSource = false
    private var captureQuality: CaptureQuality = .native
    private var controlsHeight: CGFloat = 164
    private var controlsMaxHeight: CGFloat = 460
    private(set) var options = PinOptions()
    private var suppression = CapturePresentationSuppression()
    private var suppressionStopTask: Task<Void, Never>?
    private var suppressionStopGeneration: UInt64 = 0
    private var cropPanel: CaptureRegionSelectionPanel?
    private var activity = CapturedPictureActivity()
    private var activityTask: Task<Void, Never>?
    private var lastActivitySampleTime: TimeInterval = -.infinity
    private var effectiveFrameRate = PinFrameRate.thirty
    private var referenceFrame: CGRect?

    init(id: UUID = UUID(), target: ResolvedTarget) {
        self.id = id
        descriptor = target.descriptor
        coordinateSpace = target.coordinateSpace
        applicationName = target.window.owningApplication?.applicationName
            ?? target.descriptor.ownerName
            ?? "App"
        bundleIdentifier = target.window.owningApplication?.bundleIdentifier
            ?? target.descriptor.ownerBundleIdentifier
        windowTitle = Self.displayTitle(
            target.window.title,
            fallback: applicationName
        )
    }

    var state: PinState {
        machine.state
    }

    var sourceWindowID: CGWindowID {
        descriptor.id
    }

    var needsWindowTracking: Bool {
        !suppression.isSuppressed && (state == .starting || state == .live)
    }

    var overlayWindowID: CGWindowID? {
        guard let windowNumber = panel?.windowNumber, windowNumber > 0 else {
            return nil
        }
        return CGWindowID(windowNumber)
    }

    var snapshot: PinSnapshot {
        PinSnapshot(
            id: id,
            sourceWindowID: sourceWindowID,
            applicationName: applicationName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            state: state,
            errorMessage: errorMessage,
            captureQuality: captureQuality,
            options: options,
            isHidden: suppression.isSuppressed,
            isIdle: activity.isIdle
        )
    }

    func startInitialCapture(with target: ResolvedTarget) async throws {
        let initialRevision = suppression.revision
        do {
            try transition(.targetResolved)
            createPresentationIfNeeded()
            guard !suppression.isSuppressed else { notifyChange(); return }
            try await beginCapture(
                with: target,
                preservingFrozenImage: false,
                resumingFrom: nil
            )
        } catch {
            if case PinSessionError.captureStartInterrupted = error,
               suppression.revision != initialRevision,
               state == .starting || state == .live || snapshot.canResume { return }
            await handleStartFailure(error)
            throw error
        }
    }

    func freeze(reason: PinFreezeReason = .manual) async throws {
        guard state == .live else {
            throw PinSessionError.invalidTransition(
                .invalidTransition(from: state, event: .freeze(reason))
            )
        }
        guard let captureView else {
            throw PinSessionError.freezeFailed("The capture view is unavailable.")
        }

        let image: CGImage
        do {
            image = try captureView.makeFrozenImage()
        } catch {
            throw PinSessionError.freezeFailed(error.localizedDescription)
        }

        captureView.presentFrozen(image)
        // A transient source can close in the small gap between receiving the
        // first frame and the deferred live reveal. A valid frozen frame must
        // always make its presentation visible independently of the old stream.
        showPresentation()
        try transition(.freeze(reason))
        errorMessage = reason == .captureInterrupted
            ? "Capture was interrupted. The last complete frame is preserved."
            : nil

        let detachedCycle = detachCurrentCycle()
        notifyChange()
        await Self.stopCaptureCycle(detachedCycle)
    }

    func resume(with target: ResolvedTarget) async throws {
        guard case let .frozen(previousFreezeReason) = state,
              previousFreezeReason != .sourceClosed else {
            throw PinSessionError.invalidTransition(
                .invalidTransition(from: state, event: .resume)
            )
        }

        let initialRevision = suppression.revision
        do {
            try transition(.resume)
            updateTarget(target)
            missingObservationCount = 0
            isHandlingMissingSource = false
            errorMessage = nil
            if suppression.isSuppressed {
                // While hidden, state records the user's live intent. Pixels
                // remain hidden and capture starts only after exact restoration.
                try transition(.firstCompleteFrame)
                notifyChange()
                return
            }
            captureView?.prepareForResumeKeepingFrozenImage()
            notifyChange()
            try await beginCapture(
                with: target,
                preservingFrozenImage: true,
                resumingFrom: previousFreezeReason
            )
        } catch {
            if case PinSessionError.captureStartInterrupted = error,
               suppression.revision != initialRevision,
               state == .starting || state == .live {
                if state == .starting { try? transition(.firstCompleteFrame) }
                notifyChange()
                return
            }
            if state == .starting {
                let detachedCycle = detachCurrentCycle()
                try? transition(.resumeFailed(previousFreezeReason))
                await Self.stopCaptureCycle(detachedCycle)
            }
            errorMessage = error.localizedDescription
            notifyChange()
            throw error
        }
    }

    func setOptions(_ proposed: PinOptions) {
        guard state != .stopping, state != .stopped else { return }
        var updated = proposed
        updated.captureRegion = CaptureReferenceGeometry.sanitized(updated.captureRegion)
        let isPaused: Bool
        if case .frozen = state { isPaused = true } else { isPaused = false }
        if isPaused || suppression.isSuppressed {
            // A retained crop cannot recreate the omitted source pixels. Keep
            // its truthful region until live capture is available again, while
            // allowing unrelated visibility and performance choices to change.
            updated.captureRegion = options.captureRegion
            if updated.presentationMode == .followSource, options.captureRegion != nil {
                updated.presentationMode = .reference
            }
        }
        // Cropping is an independent reference workflow; the source-following
        // overlay always covers the source's complete bounds.
        if updated.presentationMode == .followSource { updated.captureRegion = nil }
        guard updated != options else { return }
        let previous = options
        options = updated
        if previous.captureRegion != options.captureRegion || previous.presentationMode != options.presentationMode {
            updatePresentationBehavior()
            updatePanelFrame(to: descriptor.bounds)
        }
        updateSpaceMembership()
        effectiveFrameRate = activity.isIdle && options.reducesFrameRateWhenIdle ? .one : options.frameRate
        scheduleCaptureResize(to: descriptor.bounds.size)
        onOptionsChanged?(options)
        notifyChange()
    }

    func beginCropSelection() {
        guard snapshot.canChooseArea, cropPanel == nil, let panel,
              let image = try? captureView?.makeFrozenImage() else { return }
        let revision = suppression.revision
        let chooser = CaptureRegionSelectionPanel(
            image: image, previousRegion: options.captureRegion, sourceFrame: panel.frame,
            copy: presentationModel?.copy ?? FuwaCopy(language: .automatic()),
            onSelection: { [weak self] region in
                guard let self else { return }
                self.cropPanel = nil
                guard self.suppression.allowsRestore(revision: revision), self.state == .live else { return }
                var updated = self.options
                updated.captureRegion = region
                updated.presentationMode = .reference
                self.setOptions(updated)
            }, onCancellation: { [weak self] in self?.cropPanel = nil }
        )
        cropPanel = chooser
        chooser.makeKeyAndOrderFront(nil)
    }

    /// Temporary visibility is independent of the user's manual pause intent.
    /// Detaching the stream before suspension invalidates all queued callbacks.
    func preparePresentationSuppression() {
        guard state != .stopping, state != .stopped else { return }
        hidePresentation()
        cropPanel?.dismissForTeardown()
        cropPanel = nil
        guard !suppression.isSuppressed else { return }
        _ = suppression.change(to: true)
        if let image = try? captureView?.makeFrozenImage() { captureView?.presentFrozen(image) }
        let detached = detachCurrentCycle()
        let previousStop = suppressionStopTask
        suppressionStopGeneration &+= 1
        let stopGeneration = suppressionStopGeneration
        suppressionStopTask = Task { @MainActor [weak self] in
            await previousStop?.value
            await Self.stopCaptureCycle(detached)
            if self?.suppressionStopGeneration == stopGeneration { self?.suppressionStopTask = nil }
        }
        notifyChange()
    }

    func setPresentationSuppressed(_ suppressed: Bool) async throws {
        guard state != .stopping, state != .stopped else { return }
        if suppressed {
            preparePresentationSuppression()
            await suppressionStopTask?.value
            return
        }
        guard suppressed != suppression.isSuppressed else {
            return
        }
        let revision = suppression.change(to: suppressed)
        notifyChange()
        await suppressionStopTask?.value
        guard suppression.allowsRestore(revision: revision) else { return }
        switch state {
        case .frozen:
            updatePresentationBehavior()
            updatePanelFrame(to: descriptor.bounds)
            showPresentation()
        case .starting, .live:
            do {
                let target = try await TargetResolver().resolveExact(matching: descriptor)
                guard suppression.allowsRestore(revision: revision), state == .starting || state == .live else { return }
                captureView?.prepareForResumeKeepingFrozenImage()
                try await beginCapture(with: target, preservingFrozenImage: true, resumingFrom: nil)
            } catch {
                guard suppression.allowsRestore(revision: revision) else { return }
                if case TargetResolutionError.screenRecordingPermissionDenied = error {
                    onScreenRecordingRevoked?()
                } else if case TargetResolutionError.intentDisappeared = error {
                    try? transition(.sourceDisappeared)
                    if case .frozen = state { showPresentation() } else { hidePresentation() }
                } else {
                    if state == .live, (try? captureView?.makeFrozenImage()) != nil {
                        try? await freeze(reason: .captureInterrupted)
                        errorMessage = error.localizedDescription
                    } else {
                        await failAndHide(reason: .captureFailed, message: error.localizedDescription)
                    }
                }
                notifyChange()
                throw error
            }
        default:
            break
        }
    }

    func reconcile(
        descriptor currentDescriptor: WindowDescriptor?,
        coordinateSpace currentCoordinateSpace: DisplayCoordinateSpace
    ) {
        guard needsWindowTracking else { return }

        guard
            let currentDescriptor,
            currentDescriptor.ownerPID == descriptor.ownerPID
        else {
            missingObservationCount += 1
            guard missingObservationCount >= 2, !isHandlingMissingSource else { return }
            isHandlingMissingSource = true
            guard let currentCycle else {
                isHandlingMissingSource = false
                return
            }
            let streamID = currentCycle.streamID
            let generation = currentCycle.generation
            Task { @MainActor [weak self] in
                await self?.handlePotentialSourceUnavailable(
                    streamID: streamID,
                    generation: generation
                )
            }
            return
        }

        missingObservationCount = 0
        let previousFrame = descriptor.bounds
        descriptor = currentDescriptor.preservingOwnerMetadata(from: descriptor)
        coordinateSpace = currentCoordinateSpace
        updatePanelFrame(to: currentDescriptor.bounds)

        if previousFrame.size != currentDescriptor.bounds.size {
            scheduleCaptureResize(to: currentDescriptor.bounds.size)
        }
        if previousFrame != currentDescriptor.bounds {
            onGeometryChanged?()
        }
    }

    func markSourceUnavailable() async {
        isHandlingMissingSource = true
        await handleSourceUnavailable()
    }

    /// Performs the privacy-sensitive half of teardown synchronously: every
    /// panel is hidden, every retained frame is cleared, and all callbacks are
    /// detached before any potentially slow ScreenCaptureKit stop is awaited.
    func prepareForStop() {
        suppression.stop()
        cropPanel?.dismissForTeardown()
        cropPanel = nil
        cancelFirstFrameWatchdog()

        if state == .stopped {
            hidePresentation()
            captureView?.clearAllPixels()
            return
        }

        guard teardownTask == nil else { return }

        do {
            try transition(.requestStop)
        } catch {
            // Teardown must remain best-effort even if a future state is added
            // without an explicit stop edge.
            errorMessage = error.localizedDescription
        }

        hidePresentation()
        captureView?.clearAllPixels()
        let detachedCycle = detachCurrentCycle()
        if let controlsPanel {
            panel?.removeChildWindow(controlsPanel)
            controlsPanel.close()
        }
        controlsPanel = nil
        panel?.close()
        panel = nil
        captureView = nil
        notifyChange()

        let pendingSuppressionStop = suppressionStopTask
        suppressionStopTask = nil
        teardownTask = Task { @MainActor [weak self, detachedCycle] in
            await pendingSuppressionStop?.value
            await Self.stopCaptureCycle(detachedCycle)
            guard let self else { return }
            if self.state == .stopping {
                try? self.transition(.didStop)
            }
            self.teardownTask = nil
            self.notifyChange()
        }
    }

    func stop() async {
        prepareForStop()
        let activeTeardown = teardownTask
        await activeTeardown?.value
    }

    fileprivate func receive(
        _ sampleBuffer: CMSampleBuffer,
        streamID: ObjectIdentifier,
        generation: UInt64
    ) {
        guard isCurrent(streamID: streamID, generation: generation) else { return }
        guard let receipt = captureView?.consume(sampleBuffer) else { return }
        if let currentCycle { currentCycle.hasCompleteFrame = true }
        samplePictureActivity()

        // A desktop-independent filter retains its initial pointPixelScale.
        // Complete frames carry the current display scale after a window moves.
        if let scale = CaptureView.sourcePointScale(sampleBuffer),
           let currentCycle, abs(scale - currentCycle.pointScale) > 0.001 {
            currentCycle.pointScale = scale
            scheduleCaptureResize(to: descriptor.bounds.size)
        }

        missingObservationCount = 0
        guard receipt == .firstCompleteFrame, state == .starting || state == .live else { return }

        if state == .starting {
            do {
                try transition(.firstCompleteFrame)
            } catch {
                errorMessage = error.localizedDescription
                onFailure?(error)
                return
            }
        }

        cancelFirstFrameWatchdog()
        errorMessage = nil
        notifyChange()
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.isCurrent(streamID: streamID, generation: generation) else {
                return
            }
            self.showPresentation()
            await Task.yield()
            guard self.isCurrent(streamID: streamID, generation: generation) else {
                return
            }
            self.captureView?.completeFirstPresentation()
        }
    }

    fileprivate func streamStopped(
        streamID: ObjectIdentifier,
        generation: UInt64,
        message: String
    ) {
        guard isCurrent(streamID: streamID, generation: generation) else { return }
        Task { @MainActor [weak self] in
            await self?.handleUnexpectedStreamEnd(
                streamID: streamID,
                generation: generation,
                message: message
            )
        }
    }

    fileprivate func sourceBecameInactive(
        streamID: ObjectIdentifier,
        generation: UInt64
    ) {
        guard isCurrent(streamID: streamID, generation: generation) else { return }
        guard !isHandlingMissingSource else { return }
        isHandlingMissingSource = true
        Task { @MainActor [weak self] in
            await self?.handleSourceUnavailable(
                streamID: streamID,
                generation: generation
            )
        }
    }

    private func beginCapture(
        with target: ResolvedTarget,
        preservingFrozenImage: Bool,
        resumingFrom previousFreezeReason: PinFreezeReason?
    ) async throws {
        guard !suppression.isSuppressed, state != .stopping, state != .stopped else {
            throw PinSessionError.captureStartInterrupted
        }
        updateTarget(target)
        createPresentationIfNeeded()
        updatePanelFrame(to: target.descriptor.bounds)
        if !preservingFrozenImage {
            captureView?.clearAllPixels()
        }

        let filter = SCContentFilter(desktopIndependentWindow: target.window)
        let pointScale = max(1, CGFloat(filter.pointPixelScale))
        activity.reset()
        lastActivitySampleTime = -.infinity
        effectiveFrameRate = options.frameRate
        let configuration = Self.makeConfiguration(
            pointSize: Self.capturePointSize(
                filter: filter,
                fallback: target.descriptor.bounds.size
            ),
            pointScale: pointScale,
            captureQuality: captureQuality,
            captureRegion: options.captureRegion,
            frameRate: effectiveFrameRate
        )

        nextGeneration &+= 1
        if nextGeneration == 0 {
            nextGeneration = 1
        }
        let generation = nextGeneration
        let bridge = StreamCallbackBridge(generation: generation)
        bridge.owner = self
        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: bridge
        )
        let cycle = CaptureCycle(
            generation: generation,
            stream: stream,
            bridge: bridge,
            filter: filter,
            pointScale: pointScale,
            previousFreezeReason: previousFreezeReason
        )
        currentCycle = cycle
        startPictureActivityTracking(for: cycle)

        do {
            try stream.addStreamOutput(
                bridge,
                type: .screen,
                sampleHandlerQueue: .main
            )
            let startup = Task { @MainActor in try await stream.startCapture() }
            cycle.startupTask = startup
            try await startup.value
        } catch {
            guard currentCycle === cycle else {
                // Another operation detached this cycle and exclusively owns
                // its teardown. Never issue a second remove/stop sequence.
                throw PinSessionError.captureStartInterrupted
            }
            let teardown = detachCurrentCycle()
            await Self.stopCaptureCycle(teardown)
            throw PinSessionError.captureStartFailed(error.localizedDescription)
        }

        guard currentCycle === cycle else {
            throw PinSessionError.captureStartInterrupted
        }
        scheduleFirstFrameWatchdog(for: cycle)
    }

    private func scheduleFirstFrameWatchdog(for cycle: CaptureCycle) {
        guard currentCycle === cycle, !cycle.hasCompleteFrame, state == .starting || state == .live else { return }

        cancelFirstFrameWatchdog()
        let streamID = cycle.streamID
        let generation = cycle.generation
        let previousFreezeReason = cycle.previousFreezeReason
        firstFrameWatchdogTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.firstCompleteFrameTimeout)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            await self.handleFirstFrameTimeout(
                streamID: streamID,
                generation: generation,
                resumingFrom: previousFreezeReason
            )
        }
    }

    private func handleFirstFrameTimeout(
        streamID: ObjectIdentifier,
        generation: UInt64,
        resumingFrom previousFreezeReason: PinFreezeReason?
    ) async {
        guard isCurrent(streamID: streamID, generation: generation),
              currentCycle?.hasCompleteFrame == false,
              state == .starting || state == .live else {
            return
        }

        if state == .live {
            do {
                try await freeze(reason: .captureInterrupted)
                onFailure?(PinSessionError.captureResumeTimedOut)
            } catch {
                await failAndHide(reason: .captureFailed, message: error.localizedDescription)
            }
            return
        }

        let message = previousFreezeReason == nil
            ? "Window capture failed before the first complete frame arrived."
            : nil
        await handleFirstFrameFailure(
            reason: .captureFailed,
            message: message,
            failure: message.map { .captureFailed($0) } ?? .captureResumeTimedOut
        )
    }

    private func handleFirstFrameFailure(
        reason: PinFailureReason,
        message: String?,
        failure: PinSessionError
    ) async {
        guard state == .starting else { return }
        do {
            try transition(PinStartFailurePolicy.event(
                resumingFrom: currentCycle?.previousFreezeReason,
                failureReason: reason
            ))
        } catch {
            await failAndHide(
                reason: .captureFailed,
                message: error.localizedDescription
            )
            return
        }

        errorMessage = message
        if case .failed = state {
            hidePresentation()
            captureView?.clearAllPixels()
        }
        // A frozen result retains the independent image from before Resume.
        // Detach before suspension so late stream callbacks cannot clear it.
        let detachedCycle = detachCurrentCycle()
        notifyChange()
        onFailure?(failure)
        await Self.stopCaptureCycle(detachedCycle)
    }

    private func handleStartFailure(_ error: Error) async {
        if state == .starting {
            try? transition(.fail(.captureFailed))
        }
        errorMessage = error.localizedDescription
        hidePresentation()
        captureView?.clearAllPixels()
        let detachedCycle = detachCurrentCycle()
        await Self.stopCaptureCycle(detachedCycle)
        notifyChange()
    }

    private func handleUnexpectedStreamEnd(
        streamID: ObjectIdentifier,
        generation: UInt64,
        message: String
    ) async {
        guard isCurrent(streamID: streamID, generation: generation) else { return }

        guard CGPreflightScreenCaptureAccess() else {
            // Permission revocation is an app-wide privacy boundary. The
            // coordinator synchronously hides every panel and clears every
            // retained frame, including pins that were already frozen.
            onScreenRecordingRevoked?()
            return
        }

        let currentSource = WindowInventory.currentDescriptor(for: descriptor.id)
        let sourceStillExists = currentSource?.ownerPID == descriptor.ownerPID

        switch state {
        case .live:
            do {
                try await freeze(
                    reason: sourceStillExists ? .captureInterrupted : .sourceClosed
                )
            } catch {
                await failAndHide(
                    reason: .captureFailed,
                    message: message.isEmpty ? error.localizedDescription : message
                )
            }

        case .starting:
            await handleFirstFrameFailure(
                reason: sourceStillExists ? .captureFailed : .sourceClosedBeforeFirstFrame,
                message: message,
                failure: .captureFailed(message)
            )

        default:
            break
        }
    }

    private func handleSourceUnavailable() async {
        defer { isHandlingMissingSource = false }

        switch state {
        case .starting:
            let message = "The source window closed before the first frame arrived."
            await handleFirstFrameFailure(
                reason: .sourceClosedBeforeFirstFrame,
                message: message,
                failure: .captureFailed(message)
            )

        case .live:
            do {
                try await freeze(reason: .sourceClosed)
            } catch {
                await failAndHide(
                    reason: .captureFailed,
                    message: error.localizedDescription
                )
            }

        case .frozen:
            try? transition(.sourceDisappeared)
            notifyChange()

        default:
            break
        }
    }

    private func handleSourceUnavailable(
        streamID: ObjectIdentifier,
        generation: UInt64
    ) async {
        guard isCurrent(streamID: streamID, generation: generation) else {
            isHandlingMissingSource = false
            return
        }
        await handleSourceUnavailable()
    }

    private func handlePotentialSourceUnavailable(
        streamID: ObjectIdentifier,
        generation: UInt64
    ) async {
        guard isCurrent(streamID: streamID, generation: generation),
              missingObservationCount >= 2 else {
            isHandlingMissingSource = false
            return
        }

        if WindowInventory.currentDescriptor(
            for: descriptor.id,
            ownerPID: descriptor.ownerPID
        ) != nil {
            missingObservationCount = 0
            isHandlingMissingSource = false
            return
        }
        await handleSourceUnavailable()
    }

    private func failAndHide(reason: PinFailureReason, message: String) async {
        if state != .failed(reason) {
            try? transition(.fail(reason))
        }
        errorMessage = message
        hidePresentation()
        captureView?.clearAllPixels()
        let detachedCycle = detachCurrentCycle()
        await Self.stopCaptureCycle(detachedCycle)
        notifyChange()
        onFailure?(PinSessionError.captureFailed(message))
    }

    private func createPresentationIfNeeded() {
        guard panel == nil else { return }

        let frame = coordinateSpace.appKitFrame(fromQuartzFrame: descriptor.bounds)
        let view = CaptureView(frame: NSRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none

        self.panel = panel
        captureView = view
        view.onReferenceFrameChanged = { [weak self] in
            guard let self else { return }
            self.referenceFrame = self.panel?.frame
            self.positionControls()
        }
        updatePresentationBehavior()
        updateSpaceMembership()
        if let presentationModel {
            let controls = PinControlsPanel(
                contentRect: NSRect(x: frame.minX, y: frame.maxY, width: 380, height: controlsHeight),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            controlsMaxHeight = maximumControlsHeight(for: panel.frame)
            controls.contentView = NSHostingView(rootView: makeControlsView(model: presentationModel))
            controls.title = "Fuwa — \(windowTitle)"
            controls.level = .floating
            controls.isReleasedWhenClosed = false
            controls.hidesOnDeactivate = true
            controls.sharingType = .none
            controls.collectionBehavior = panel.collectionBehavior
            controlsPanel = controls
        }
        updatePanelFrame(to: descriptor.bounds)
    }

    func reconcileDisplayArrangement() {
        guard let panel else { return }
        if options.presentationMode == .reference || snapshot.canShowControls {
            let recovered = FloatingControlsLayout.recoveredFrame(
                source: panel.frame, visibleScreens: NSScreen.screens.map(\.visibleFrame)
            )
            if recovered != panel.frame {
                panel.setFrame(recovered, display: true)
                if options.presentationMode == .reference { referenceFrame = recovered }
            }
        }
        positionControls()
    }

    func focusControls() {
        guard let panel, panel.isVisible, let controlsPanel else { return }
        reconcileDisplayArrangement()
        if controlsPanel.parent == nil { panel.addChildWindow(controlsPanel, ordered: .above) }
        controlsPanel.makeKeyAndOrderFront(nil)
    }

    private func showPresentation() {
        guard !suppression.isSuppressed, state != .stopping, state != .stopped else { return }
        panel?.orderFrontRegardless()
    }

    private func hidePresentation() {
        if let controlsPanel, controlsPanel.parent != nil { panel?.removeChildWindow(controlsPanel) }
        controlsPanel?.orderOut(nil)
        panel?.orderOut(nil)
    }

    private func positionControls() {
        guard let panel, let controlsPanel else { return }
        let screens = NSScreen.screens
        guard let index = FloatingControlsLayout.screenIndex(source: panel.frame, screens: screens.map(\.frame)) else { return }
        let maxHeight = max(120, min(460, screens[index].visibleFrame.height - 16))
        if abs(controlsMaxHeight - maxHeight) > 0.5,
           let host = controlsPanel.contentView as? NSHostingView<PinControlsView>, let presentationModel {
            controlsMaxHeight = maxHeight
            host.rootView = makeControlsView(model: presentationModel)
        }
        let frame = FloatingControlsLayout.frame(source: panel.frame, visible: screens[index].visibleFrame,
                                                 size: CGSize(width: 380, height: min(controlsHeight, maxHeight)))
        if controlsPanel.frame != frame { controlsPanel.setFrame(frame, display: true) }
    }

    private func updateTarget(_ target: ResolvedTarget) {
        descriptor = target.descriptor
        coordinateSpace = target.coordinateSpace
        applicationName = target.window.owningApplication?.applicationName
            ?? target.descriptor.ownerName
            ?? applicationName
        bundleIdentifier = target.window.owningApplication?.bundleIdentifier
            ?? target.descriptor.ownerBundleIdentifier
            ?? bundleIdentifier
        windowTitle = Self.displayTitle(target.window.title, fallback: applicationName)
    }

    private func updatePanelFrame(to quartzFrame: CGRect) {
        if options.presentationMode == .reference, let panel {
            let aspect = presentationAspect
            // Native dragging can run a nested AppKit loop. Read the current
            // frame so tracker callbacks cannot snap an in-progress drag back
            // to a cached position from before the drag began.
            let initial = panel.frame
            let resized = CaptureReferenceGeometry.resizedFrame(initial, requestedWidth: initial.width, aspect: aspect,
                                                                maximumSize: maximumReferenceSize(for: initial))
            let recovered = FloatingControlsLayout.recoveredFrame(source: resized,
                                                                 visibleScreens: NSScreen.screens.map(\.visibleFrame))
            if panel.frame != recovered { panel.setFrame(recovered, display: true) }
            referenceFrame = recovered
            captureView?.referenceAspect = aspect
            positionControls()
            return
        }
        let appKitFrame = coordinateSpace.appKitFrame(fromQuartzFrame: quartzFrame)
        guard appKitFrame.width > 0, appKitFrame.height > 0 else { return }
        if panel?.frame != appKitFrame { panel?.setFrame(appKitFrame, display: true) }
        // Screen usable bounds can change even when the source window does not.
        positionControls()
    }

    private var presentationAspect: CGSize {
        if case .frozen = state, let image = try? captureView?.makeFrozenImage() {
            return CGSize(width: image.width, height: image.height)
        }
        return CaptureReferenceGeometry.sourceRect(pointSize: descriptor.bounds.size, region: options.captureRegion).size
    }

    private func updatePresentationBehavior() {
        guard let panel, let captureView else { return }
        let reference = options.presentationMode == .reference
        let wasReference = captureView.isReferencePresentation
        if reference && !wasReference {
            let saved = referenceFrame ?? CaptureReferenceGeometry.resizedFrame(
                panel.frame, requestedWidth: min(640, panel.frame.width), aspect: presentationAspect,
                maximumSize: maximumReferenceSize(for: panel.frame)
            )
            let restored = CaptureReferenceGeometry.resizedFrame(saved, requestedWidth: saved.width,
                                                                 aspect: presentationAspect,
                                                                 maximumSize: maximumReferenceSize(for: saved))
            let recovered = FloatingControlsLayout.recoveredFrame(source: restored,
                                                                 visibleScreens: NSScreen.screens.map(\.visibleFrame))
            panel.setFrame(recovered, display: true)
            referenceFrame = recovered
        } else if !reference && wasReference {
            referenceFrame = panel.frame
        }
        panel.ignoresMouseEvents = !reference
        panel.isMovable = reference
        panel.isMovableByWindowBackground = reference
        captureView.isReferencePresentation = reference
        captureView.referenceAspect = presentationAspect
        captureView.toolTip = reference ? (presentationModel?.copy ?? FuwaCopy(language: .automatic())).text(.referenceInstructions) : nil
    }

    private func updateSpaceMembership() {
        var membership: NSWindow.CollectionBehavior = [.canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        if options.spaceScope == .allSpaces { membership.insert(.canJoinAllSpaces) }
        panel?.collectionBehavior = membership
        controlsPanel?.collectionBehavior = membership
    }

    private func maximumControlsHeight(for frame: CGRect) -> CGFloat {
        guard let index = FloatingControlsLayout.screenIndex(source: frame, screens: NSScreen.screens.map(\.frame)) else { return 460 }
        return max(120, min(460, NSScreen.screens[index].visibleFrame.height - 16))
    }

    private func maximumReferenceSize(for frame: CGRect) -> CGSize? {
        guard let index = FloatingControlsLayout.screenIndex(source: frame, screens: NSScreen.screens.map(\.frame)) else { return nil }
        return NSScreen.screens[index].visibleFrame.insetBy(dx: 8, dy: 8).size
    }

    func refreshPresentationCopy() {
        updatePresentationBehavior()
        updateIdleIndicator()
        // An open selector uses a static source image and localized instructions.
        // Close it on a language switch so reopening uses the selected language.
        cropPanel?.dismissForTeardown()
        cropPanel = nil
    }

    private func makeControlsView(model: AppModel) -> PinControlsView {
        PinControlsView(model: model, pinID: id, maximumHeight: controlsMaxHeight,
                        onHeightChanged: { [weak self] height in
            guard let self, height > 0, abs(height - self.controlsHeight) > 0.5 else { return }
            self.controlsHeight = height
            self.positionControls()
        })
    }

    private func scheduleCaptureResize(to pointSize: CGSize) {
        guard let currentCycle else { return }

        let latestScale = currentCycle.pointScale
        let configuration = Self.makeConfiguration(
            pointSize: pointSize,
            pointScale: latestScale,
            captureQuality: captureQuality,
            captureRegion: options.captureRegion,
            frameRate: effectiveFrameRate
        )
        let generation = currentCycle.generation
        let streamID = currentCycle.streamID
        let stream = currentCycle.stream
        let previousResize = resizeTask
        previousResize?.cancel()

        resizeTask = Task { @MainActor [weak self] in
            await previousResize?.value
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            guard let self, self.isCurrent(streamID: streamID, generation: generation) else {
                return
            }
            do {
                try await stream.updateConfiguration(configuration)
                guard self.isCurrent(streamID: streamID, generation: generation) else {
                    return
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.notifyChange()
            }
        }
    }

    func setCaptureQuality(_ quality: CaptureQuality) {
        guard state == .live, quality != captureQuality else { return }
        captureQuality = quality
        scheduleCaptureResize(to: descriptor.bounds.size)
        notifyChange()
    }

    private func startPictureActivityTracking(for cycle: CaptureCycle) {
        activityTask?.cancel()
        let streamID = cycle.streamID, generation = cycle.generation
        activityTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.isCurrent(streamID: streamID, generation: generation) else { return }
                if self.activity.evaluate(at: ProcessInfo.processInfo.systemUptime) {
                    self.applyPictureActivityChange()
                }
            }
        }
    }

    private func samplePictureActivity() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastActivitySampleTime >= 0.5, let sampled = captureView?.activitySamples() else { return }
        lastActivitySampleTime = now
        let wasIdle = activity.isIdle
        _ = activity.observe(samples: sampled.samples, dimensions: sampled.dimensions, at: now)
        if wasIdle != activity.isIdle { applyPictureActivityChange() }
    }

    private func applyPictureActivityChange() {
        let desired: PinFrameRate = activity.isIdle && options.reducesFrameRateWhenIdle ? .one : options.frameRate
        if desired != effectiveFrameRate {
            effectiveFrameRate = desired
            scheduleCaptureResize(to: descriptor.bounds.size)
        }
        notifyChange()
    }

    private func updateIdleIndicator() {
        let show = state == .live && options.notifiesWhenIdle && activity.isIdle && !suppression.isSuppressed
        let copy = presentationModel?.copy ?? FuwaCopy(language: .automatic())
        captureView?.setIdleIndicator(title: show ? copy.text(.pictureIdle) : nil,
                                     explanation: show ? copy.text(.pictureIdleNote) : nil)
    }

    static func makeConfiguration(
        pointSize: CGSize,
        pointScale: CGFloat,
        captureQuality: CaptureQuality = .default,
        captureRegion: NormalizedCaptureRegion? = nil,
        frameRate: PinFrameRate = .thirty
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let sourceRect = CaptureReferenceGeometry.sourceRect(pointSize: pointSize, region: captureRegion)
        let sizingSize = CaptureReferenceGeometry.pixelStablePointSize(sourceRect.size, pointScale: pointScale)
        let dimensions = LiveCaptureSizing.fittedDimensions(
            pointWidth: Double(sizingSize.width),
            pointHeight: Double(sizingSize.height),
            pointScale: Double(pointScale),
            quality: captureQuality
        ) ?? PixelDimensions(width: 2, height: 2)
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        if CaptureReferenceGeometry.sanitized(captureRegion) != nil { configuration.sourceRect = sourceRect }
        if captureQuality == .native { configuration.captureResolution = .best }
        // Fill the canvas while a cross-display resize is being applied.
        configuration.scalesToFit = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(frameRate.rawValue))
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        return configuration
    }

    private func transition(_ event: PinEvent) throws {
        do {
            _ = try machine.apply(event)
        } catch let error as PinTransitionError {
            throw PinSessionError.invalidTransition(error)
        }
    }

    private func detachCurrentCycle() -> CaptureTeardown? {
        cancelFirstFrameWatchdog()
        activityTask?.cancel()
        activityTask = nil
        activity.reset()
        lastActivitySampleTime = -.infinity
        let detachedResizeTask = resizeTask
        detachedResizeTask?.cancel()
        resizeTask = nil
        guard let detachedCycle = currentCycle else { return nil }
        currentCycle = nil
        detachedCycle.bridge.owner = nil
        return CaptureTeardown(
            cycle: detachedCycle,
            resizeTask: detachedResizeTask
        )
    }

    private func cancelFirstFrameWatchdog() {
        firstFrameWatchdogTask?.cancel()
        firstFrameWatchdogTask = nil
    }

    private static func stopCaptureCycle(_ teardown: CaptureTeardown?) async {
        guard let teardown else { return }
        await teardown.resizeTask?.value
        let cycle = teardown.cycle
        // A stop issued before asynchronous startup finishes can return early
        // and leave a detached stream running. The sole teardown owner waits
        // for startup (success or failure) before removing output and stopping.
        _ = await cycle.startupTask?.result
        try? cycle.stream.removeStreamOutput(cycle.bridge, type: .screen)
        try? await cycle.stream.stopCapture()
    }

    private func isCurrent(streamID: ObjectIdentifier, generation: UInt64) -> Bool {
        guard let currentCycle else { return false }
        return currentCycle.generation == generation && currentCycle.streamID == streamID
    }

    private func notifyChange() {
        updateIdleIndicator()
        onChange?()
    }

    private static func capturePointSize(
        filter: SCContentFilter,
        fallback: CGSize
    ) -> CGSize {
        let contentSize = filter.contentRect.size
        guard contentSize.width > 0, contentSize.height > 0 else { return fallback }
        return contentSize
    }

    private static func displayTitle(_ title: String?, fallback: String) -> String {
        guard let title else { return fallback }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

@MainActor
private final class CaptureTeardown {
    let cycle: CaptureCycle
    let resizeTask: Task<Void, Never>?

    init(cycle: CaptureCycle, resizeTask: Task<Void, Never>?) {
        self.cycle = cycle
        self.resizeTask = resizeTask
    }
}

@MainActor
private final class CaptureCycle {
    let generation: UInt64
    let stream: SCStream
    let streamID: ObjectIdentifier
    let bridge: StreamCallbackBridge
    let filter: SCContentFilter
    let previousFreezeReason: PinFreezeReason?
    var pointScale: CGFloat
    var hasCompleteFrame = false
    var startupTask: Task<Void, Error>?

    init(
        generation: UInt64,
        stream: SCStream,
        bridge: StreamCallbackBridge,
        filter: SCContentFilter,
        pointScale: CGFloat,
        previousFreezeReason: PinFreezeReason?
    ) {
        self.generation = generation
        self.stream = stream
        streamID = ObjectIdentifier(stream)
        self.bridge = bridge
        self.filter = filter
        self.pointScale = pointScale
        self.previousFreezeReason = previousFreezeReason
    }
}

@MainActor
private final class StreamCallbackBridge: NSObject,
    @preconcurrency SCStreamOutput,
    SCStreamDelegate
{
    nonisolated let generation: UInt64
    weak var owner: PinSession?

    init(generation: UInt64) {
        self.generation = generation
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen else { return }
        owner?.receive(
            sampleBuffer,
            streamID: ObjectIdentifier(stream),
            generation: generation
        )
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let streamID = ObjectIdentifier(stream)
        let generation = generation
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.owner?.streamStopped(
                streamID: streamID,
                generation: generation,
                message: message
            )
        }
    }

    @available(macOS 15.2, *)
    nonisolated func streamDidBecomeInactive(_ stream: SCStream) {
        let streamID = ObjectIdentifier(stream)
        let generation = generation
        Task { @MainActor [weak self] in
            self?.owner?.sourceBecameInactive(
                streamID: streamID,
                generation: generation
            )
        }
    }
}
