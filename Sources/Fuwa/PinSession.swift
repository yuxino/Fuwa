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

    var canAdjustQuality: Bool { state == .live }

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
        state == .starting || state == .live
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
            captureQuality: captureQuality
        )
    }

    func startInitialCapture(with target: ResolvedTarget) async throws {
        do {
            try transition(.targetResolved)
            createPresentationIfNeeded()
            try await beginCapture(
                with: target,
                preservingFrozenImage: false,
                resumingFrom: nil
            )
        } catch {
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

        do {
            try transition(.resume)
            updateTarget(target)
            missingObservationCount = 0
            isHandlingMissingSource = false
            errorMessage = nil
            captureView?.prepareForResumeKeepingFrozenImage()
            notifyChange()
            try await beginCapture(
                with: target,
                preservingFrozenImage: true,
                resumingFrom: previousFreezeReason
            )
        } catch {
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

        teardownTask = Task { @MainActor [weak self, detachedCycle] in
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

        // A desktop-independent filter retains its initial pointPixelScale.
        // Complete frames carry the current display scale after a window moves.
        if let scale = CaptureView.sourcePointScale(sampleBuffer),
           let currentCycle, abs(scale - currentCycle.pointScale) > 0.001 {
            currentCycle.pointScale = scale
            scheduleCaptureResize(to: descriptor.bounds.size)
        }

        missingObservationCount = 0
        guard receipt == .firstCompleteFrame, state == .starting else { return }

        do {
            try transition(.firstCompleteFrame)
        } catch {
            errorMessage = error.localizedDescription
            onFailure?(error)
            return
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
        updateTarget(target)
        createPresentationIfNeeded()
        updatePanelFrame(to: target.descriptor.bounds)
        if !preservingFrozenImage {
            captureView?.clearAllPixels()
        }

        let filter = SCContentFilter(desktopIndependentWindow: target.window)
        let pointScale = max(1, CGFloat(filter.pointPixelScale))
        let configuration = Self.makeConfiguration(
            pointSize: Self.capturePointSize(
                filter: filter,
                fallback: target.descriptor.bounds.size
            ),
            pointScale: pointScale,
            captureQuality: captureQuality
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

        do {
            try stream.addStreamOutput(
                bridge,
                type: .screen,
                sampleHandlerQueue: .main
            )
            try await stream.startCapture()
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
        guard currentCycle === cycle, state == .starting else { return }

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
              state == .starting else {
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
        if let presentationModel {
            let controls = PinControlsPanel(
                contentRect: NSRect(x: frame.minX, y: frame.maxY, width: 380, height: controlsHeight),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            controls.contentView = NSHostingView(rootView: PinControlsView(
                model: presentationModel, pinID: id,
                onHeightChanged: { [weak self] height in
                    guard let self, height > 0, abs(height - controlsHeight) > 0.5 else { return }
                    controlsHeight = height
                    positionControls()
                }
            ))
            controls.title = "Fuwa — \(windowTitle)"
            controls.level = .floating
            controls.isReleasedWhenClosed = false
            controls.hidesOnDeactivate = true
            controls.sharingType = .none
            controls.collectionBehavior = panel.collectionBehavior
            controlsPanel = controls
        }
    }

    func reconcileDisplayArrangement() {
        guard let panel else { return }
        if case .frozen = state {
            let recovered = FloatingControlsLayout.recoveredFrame(
                source: panel.frame, visibleScreens: NSScreen.screens.map(\.visibleFrame)
            )
            if recovered != panel.frame { panel.setFrame(recovered, display: true) }
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
        panel?.orderFrontRegardless()
    }

    private func hidePresentation() {
        controlsPanel?.orderOut(nil)
        panel?.orderOut(nil)
    }

    private func positionControls() {
        guard let panel, let controlsPanel else { return }
        let screens = NSScreen.screens
        guard let index = FloatingControlsLayout.screenIndex(source: panel.frame, screens: screens.map(\.frame)) else { return }
        let frame = FloatingControlsLayout.frame(source: panel.frame, visible: screens[index].visibleFrame,
                                                 size: CGSize(width: 380, height: controlsHeight))
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
        let appKitFrame = coordinateSpace.appKitFrame(fromQuartzFrame: quartzFrame)
        guard appKitFrame.width > 0, appKitFrame.height > 0 else { return }
        if panel?.frame != appKitFrame { panel?.setFrame(appKitFrame, display: true) }
        // Screen usable bounds can change even when the source window does not.
        positionControls()
    }

    private func scheduleCaptureResize(to pointSize: CGSize) {
        guard let currentCycle else { return }

        let latestScale = currentCycle.pointScale
        let configuration = Self.makeConfiguration(
            pointSize: pointSize,
            pointScale: latestScale,
            captureQuality: captureQuality
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

    static func makeConfiguration(
        pointSize: CGSize,
        pointScale: CGFloat,
        captureQuality: CaptureQuality = .default
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let dimensions = LiveCaptureSizing.fittedDimensions(
            pointWidth: Double(pointSize.width),
            pointHeight: Double(pointSize.height),
            pointScale: Double(pointScale),
            quality: captureQuality
        ) ?? PixelDimensions(width: 2, height: 2)
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        if captureQuality == .native { configuration.captureResolution = .best }
        // Fill the canvas while a cross-display resize is being applied.
        configuration.scalesToFit = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
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
        try? cycle.stream.removeStreamOutput(cycle.bridge, type: .screen)
        try? await cycle.stream.stopCapture()
    }

    private func isCurrent(streamID: ObjectIdentifier, generation: UInt64) -> Bool {
        guard let currentCycle else { return false }
        return currentCycle.generation == generation && currentCycle.streamID == streamID
    }

    private func notifyChange() {
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
