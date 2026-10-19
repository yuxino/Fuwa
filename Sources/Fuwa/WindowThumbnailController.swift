import AppKit
import Combine
import FuwaCore
import ScreenCaptureKit
import SwiftUI

struct WindowThumbnailIdentity: Hashable, Sendable {
    let windowID: CGWindowID
    let ownerPID: pid_t

    init(_ descriptor: WindowDescriptor) {
        windowID = descriptor.id
        ownerPID = descriptor.ownerPID
    }
}

/// AppModel owns this bounded, memory-only cache across picker presentations.
/// Requests that outlive a dismissed row, refresh, or privacy boundary can never
/// repopulate its pixels or exceed the concurrency limit when the picker reopens.
@MainActor
final class WindowThumbnailController: ObservableObject {
    typealias Capture = @MainActor (WindowDescriptor) async throws -> CGImage?
    typealias IdentityCheck = @MainActor (WindowDescriptor) -> Bool

    static let maximumConcurrentRequests = 2
    static let maximumRetainedThumbnails = 24
    static let maximumPixelWidth = 256
    static let maximumPixelHeight = 160

    @Published private(set) var privacyInvalidated = false
    private(set) var isActive = false
    private let permissionGranted: @MainActor () -> Bool
    private let identityIsCurrent: IdentityCheck
    private let capture: Capture
    private let selfProcessID: pid_t
    private let privacyLifecycle = PrivacyLifecycle()
    private var terminationObserver: NSObjectProtocol?
    private var permissionTask: Task<Void, Never>?
    private var hasSeenPermission = false
    private var generation: UInt64 = 0
    private var desired: [WindowThumbnailIdentity: WindowDescriptor] = [:]
    private var queue: [WindowThumbnailIdentity] = []
    private var requests: [UUID: Task<Void, Never>] = [:]
    private var inFlight: [WindowThumbnailIdentity: UUID] = [:]
    private var images: [WindowThumbnailIdentity: CGImage] = [:]
    private var views: [ObjectIdentifier: WeakThumbnailView] = [:]

    init(permissionGranted: @escaping @MainActor () -> Bool = { CGPreflightScreenCaptureAccess() },
         identityIsCurrent: @escaping IdentityCheck = WindowThumbnailController.isCurrent,
         capture: @escaping Capture = WindowThumbnailController.captureThumbnail,
         selfProcessID: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.permissionGranted = permissionGranted
        self.identityIsCurrent = identityIsCurrent
        self.capture = capture
        self.selfProcessID = selfProcessID
    }

    isolated deinit { stop() }

    func start(observesPrivacy: Bool = true) {
        guard !isActive else { return }
        isActive = true
        privacyInvalidated = false
        hasSeenPermission = permissionGranted()
        guard observesPrivacy else { return }
        privacyLifecycle.onPrivacyBoundary = { [weak self] _ in self?.invalidatePrivacy() }
        privacyLifecycle.onEnvironmentRefresh = { [weak self] in self?.checkPermission() }
        privacyLifecycle.start()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidatePrivacy() }
        }
        permissionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
                guard !Task.isCancelled, let self, self.isActive else { return }
                self.checkPermission()
            }
        }
    }

    func stop() {
        isActive = false
        reset()
        permissionTask?.cancel()
        permissionTask = nil
        privacyLifecycle.stop()
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        terminationObserver = nil
    }

    func reset() {
        generation &+= 1
        desired.removeAll()
        queue.removeAll()
        requests.values.forEach { $0.cancel() }
        // In-flight screenshot APIs have no cancellation handle. Keep their
        // slots occupied until completion so rapid refresh or reopening the
        // picker stays bounded.
        images.removeAll()
        for entry in views.values { entry.view?.present(nil) }
    }

    func invalidatePrivacy() {
        stop()
        privacyInvalidated = true
    }

    func checkPermission() {
        guard isActive else { return }
        if permissionGranted() { hasSeenPermission = true }
        else if hasSeenPermission { invalidatePrivacy() }
    }

    func request(_ descriptor: WindowDescriptor) {
        guard isActive, descriptor.ownerPID != selfProcessID else { return }
        guard permissionGranted() else { checkPermission(); return }
        hasSeenPermission = true
        guard identityIsCurrent(descriptor) else { return }
        let identity = WindowThumbnailIdentity(descriptor)
        guard desired[identity] != nil || desired.count < Self.maximumRetainedThumbnails else { return }
        desired[identity] = descriptor
        guard images[identity] == nil else { return }
        if !queue.contains(identity) { queue.append(identity) }
        drain()
    }

    func release(_ descriptor: WindowDescriptor) {
        let identity = WindowThumbnailIdentity(descriptor)
        desired.removeValue(forKey: identity)
        queue.removeAll { $0 == identity }
        images.removeValue(forKey: identity)
        if let requestID = inFlight[identity] { requests[requestID]?.cancel() }
        present(nil, for: identity)
    }

    func register(_ view: WindowThumbnailImageView, for descriptor: WindowDescriptor) {
        let identity = WindowThumbnailIdentity(descriptor)
        views[ObjectIdentifier(view)] = WeakThumbnailView(view: view, identity: identity)
        view.present(images[identity])
    }

    func unregister(_ view: WindowThumbnailImageView) {
        views.removeValue(forKey: ObjectIdentifier(view))
        view.present(nil)
    }

    // Internal inspection points for lifecycle tests; never expose pixel data.
    var retainedImageCount: Int { images.count }
    var activeRequestCount: Int { requests.count }

    private func drain() {
        guard isActive else { return }
        guard permissionGranted() else { checkPermission(); return }
        while requests.count < Self.maximumConcurrentRequests,
              let index = queue.firstIndex(where: { inFlight[$0] == nil }) {
            let identity = queue.remove(at: index)
            guard let descriptor = desired[identity], images[identity] == nil,
                  descriptor.ownerPID != selfProcessID, identityIsCurrent(descriptor) else { continue }
            let requestID = UUID()
            let revision = generation
            let provider = capture
            inFlight[identity] = requestID
            requests[requestID] = Task { @MainActor [weak self] in
                var image: CGImage?
                if !Task.isCancelled { image = try? await provider(descriptor) }
                self?.complete(requestID, identity: identity, descriptor: descriptor,
                               revision: revision, image: image, cancelled: Task.isCancelled)
            }
        }
    }

    private func complete(_ requestID: UUID, identity: WindowThumbnailIdentity,
                          descriptor: WindowDescriptor, revision: UInt64,
                          image: CGImage?, cancelled: Bool) {
        requests.removeValue(forKey: requestID)
        if inFlight[identity] == requestID { inFlight.removeValue(forKey: identity) }
        guard isActive else { return }
        guard permissionGranted() else { invalidatePrivacy(); return }
        if !cancelled, revision == generation, desired[identity] != nil,
           identityIsCurrent(descriptor), let image,
           image.width <= Self.maximumPixelWidth, image.height <= Self.maximumPixelHeight {
            images[identity] = image
            present(image, for: identity)
            queue.removeAll { $0 == identity }
        } else if (cancelled || revision != generation), desired[identity] != nil {
            if !queue.contains(identity) { queue.append(identity) }
        } else {
            queue.removeAll { $0 == identity }
        }
        drain()
    }

    private func present(_ image: CGImage?, for identity: WindowThumbnailIdentity) {
        views = views.filter { $0.value.view != nil }
        for entry in views.values where entry.identity == identity { entry.view?.present(image) }
    }

    static func dimensions(for size: CGSize) -> PixelDimensions? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let scale = min(CGFloat(maximumPixelWidth) / size.width, CGFloat(maximumPixelHeight) / size.height)
        guard scale.isFinite, scale > 0 else { return nil }
        return PixelDimensions(width: max(2, min(maximumPixelWidth, Int((size.width * scale).rounded(.down)))),
                               height: max(2, min(maximumPixelHeight, Int((size.height * scale).rounded(.down)))))
    }

    private static func isCurrent(_ descriptor: WindowDescriptor) -> Bool {
        guard descriptor.ownerPID != ProcessInfo.processInfo.processIdentifier,
              let current = WindowInventory.currentDescriptor(for: descriptor.id, ownerPID: descriptor.ownerPID) else { return false }
        return descriptor.ownerBundleIdentifier == nil || current.ownerBundleIdentifier == descriptor.ownerBundleIdentifier
    }

    private static func captureThumbnail(_ descriptor: WindowDescriptor) async throws -> CGImage? {
        guard !Task.isCancelled, CGPreflightScreenCaptureAccess(), isCurrent(descriptor) else { return nil }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard !Task.isCancelled, CGPreflightScreenCaptureAccess(), isCurrent(descriptor),
              let window = content.windows.first(where: { $0.windowID == descriptor.id }),
              window.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier else { return nil }
        // Match PID through WindowServer before and after each suspension.
        // ScreenCaptureKit may attribute system-hosted Quick Look windows to a
        // different host process; its PID is not Fuwa's identity authority.
        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let size = dimensions(for: filter.contentRect.size) else { return nil }
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.shouldBeOpaque = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard !Task.isCancelled, CGPreflightScreenCaptureAccess(), isCurrent(descriptor) else { return nil }
        return image
    }
}

@MainActor
private struct WeakThumbnailView {
    weak var view: WindowThumbnailImageView?
    let identity: WindowThumbnailIdentity
}

/// A native image layer lets privacy boundaries clear displayed pixels
/// synchronously, without waiting for a SwiftUI image diff or a retained NSImage.
@MainActor
final class WindowThumbnailImageView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.backgroundColor = NSColor(white: 0.975, alpha: 1).cgColor
        layer?.masksToBounds = true
        isHidden = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        isHidden = image == nil
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
struct WindowThumbnailView: NSViewRepresentable {
    let controller: WindowThumbnailController
    let descriptor: WindowDescriptor

    func makeCoordinator() -> WindowThumbnailController { controller }

    func makeNSView(context: Context) -> WindowThumbnailImageView {
        let view = WindowThumbnailImageView(frame: .zero)
        controller.register(view, for: descriptor)
        return view
    }

    func updateNSView(_ view: WindowThumbnailImageView, context: Context) {
        controller.register(view, for: descriptor)
    }

    static func dismantleNSView(_ view: WindowThumbnailImageView, coordinator: WindowThumbnailController) {
        coordinator.unregister(view)
    }
}
