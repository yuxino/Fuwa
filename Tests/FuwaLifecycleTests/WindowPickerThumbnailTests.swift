import AppKit
import CoreGraphics
import FuwaCore
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct WindowPickerThumbnailTests {
    @Test func thumbnailDimensionsStaySmallAndRejectInvalidGeometry() {
        #expect(WindowThumbnailController.dimensions(for: CGSize(width: 1920, height: 1080))
                == PixelDimensions(width: 256, height: 144))
        #expect(WindowThumbnailController.dimensions(for: CGSize(width: 1200, height: 2400))
                == PixelDimensions(width: 80, height: 160))
        for size in [CGSize(width: 1_000_000, height: 1), CGSize(width: 1, height: 1_000_000)] {
            let pixels = WindowThumbnailController.dimensions(for: size)
            #expect(pixels != nil)
            #expect((pixels?.width ?? 0) <= 256 && (pixels?.height ?? 0) <= 160)
            #expect((pixels?.width ?? 0) >= 2 && (pixels?.height ?? 0) >= 2)
        }
        for size in [CGSize.zero, CGSize(width: -1, height: 10),
                     CGSize(width: CGFloat.infinity, height: 10),
                     CGSize(width: CGFloat.nan, height: 10),
                     CGSize(width: CGFloat.leastNonzeroMagnitude, height: CGFloat.leastNonzeroMagnitude)] {
            #expect(WindowThumbnailController.dimensions(for: size) == nil)
        }
    }

    @Test func permissionAndSelfExclusionAreCheckedBeforeCapture() async throws {
        let probe = ThumbnailCaptureProbe()
        let environment = ThumbnailEnvironmentProbe()
        environment.permitted = false
        let controller = WindowThumbnailController(permissionGranted: { environment.permitted }, identityIsCurrent: { _ in true },
            capture: probe.capture, selfProcessID: 999)
        defer { controller.stop(); probe.completeAll(with: nil) }
        controller.start(observesPrivacy: false)
        controller.request(descriptor(1))
        controller.request(descriptor(2, ownerPID: 999))
        #expect(controller.activeRequestCount == 0)
        #expect(probe.started.isEmpty)
        environment.permitted = true
        controller.request(descriptor(2, ownerPID: 999))
        controller.request(descriptor(1))
        try await settle { probe.started.count == 1 }
        #expect(probe.started.first?.id == 1)
        environment.permitted = false
        controller.checkPermission()
        #expect(controller.privacyInvalidated)
        #expect(!controller.isActive)
        probe.completeNext(with: try generatedImage())
        try await settle { controller.activeRequestCount == 0 }
        #expect(controller.retainedImageCount == 0)
    }

    @Test func recycledWindowIdentityNeverPublishesTheEarlierPixels() async throws {
        let probe = ThumbnailCaptureProbe()
        let environment = ThumbnailEnvironmentProbe()
        let controller = WindowThumbnailController(permissionGranted: { true },
            identityIsCurrent: { $0.id == 7 && $0.ownerPID == environment.currentPID }, capture: probe.capture, selfProcessID: 999)
        defer { controller.stop(); probe.completeAll(with: nil) }
        controller.start(observesPrivacy: false)
        let previous = descriptor(7)
        let view = WindowThumbnailImageView(frame: CGRect(x: 0, y: 0, width: 96, height: 60))
        controller.register(view, for: previous)
        controller.request(previous)
        try await settle { probe.started.count == 1 }
        environment.currentPID = 322
        probe.completeNext(with: try generatedImage())
        try await settle { controller.activeRequestCount == 0 }
        #expect(controller.retainedImageCount == 0)
        #expect(view.layer?.contents == nil)
        controller.request(descriptor(7, ownerPID: 322))
        try await settle { probe.started.count == 2 }
        probe.completeNext(with: try generatedImage())
        try await settle { controller.retainedImageCount == 1 }
        #expect(view.layer?.contents == nil, "The old PID's row must not show the new owner's pixels")
    }

    @Test func privacyBoundarySynchronouslyClearsNativePixelsAndRejectsLateResults() async throws {
        let image = try generatedImage()
        let probe = ThumbnailCaptureProbe()
        let controller = WindowThumbnailController(permissionGranted: { true }, identityIsCurrent: { _ in true },
            capture: { source in
                if source.id == 1 { return image }
                return await probe.capture(source)
            }, selfProcessID: 999)
        defer { controller.stop(); probe.completeAll(with: nil) }
        controller.start(observesPrivacy: false)
        let view = WindowThumbnailImageView(frame: CGRect(x: 0, y: 0, width: 96, height: 60))
        controller.register(view, for: descriptor(1))
        controller.request(descriptor(1))
        try await settle { controller.retainedImageCount == 1 }
        #expect(view.layer?.contents != nil)
        controller.request(descriptor(2))
        try await settle { probe.started.count == 1 }
        controller.invalidatePrivacy()
        #expect(controller.retainedImageCount == 0)
        #expect(view.layer?.contents == nil)
        #expect(view.isHidden)
        probe.completeNext(with: image)
        try await settle { controller.activeRequestCount == 0 }
        #expect(controller.retainedImageCount == 0)
    }

    @Test func refreshKeepsUncancellableRequestsWithinTheConcurrencyLimit() async throws {
        let probe = ThumbnailCaptureProbe()
        let controller = WindowThumbnailController(permissionGranted: { true }, identityIsCurrent: { _ in true },
            capture: probe.capture, selfProcessID: 999)
        defer { controller.stop(); probe.completeAll(with: nil) }
        controller.start(observesPrivacy: false)
        for id in 1...5 { controller.request(descriptor(CGWindowID(id))) }
        try await settle { probe.started.count == 2 }
        controller.reset()
        controller.request(descriptor(1))
        controller.request(descriptor(6))
        #expect(controller.activeRequestCount == 2)
        #expect(probe.started.count == 2)
        probe.completeNext(with: try generatedImage())
        try await settle { probe.started.count == 3 }
        probe.completeNext(with: try generatedImage())
        try await settle { probe.started.count == 4 }
        #expect(controller.retainedImageCount == 0)
        #expect(probe.maximumActive == WindowThumbnailController.maximumConcurrentRequests)
        controller.stop()
        probe.completeAll(with: try generatedImage())
        try await settle { controller.activeRequestCount == 0 }
        #expect(controller.retainedImageCount == 0)
    }

    @Test func cacheIsBoundedAndLeavingARowImmediatelyClearsItsImage() async throws {
        let image = try generatedImage()
        let controller = WindowThumbnailController(permissionGranted: { true }, identityIsCurrent: { _ in true },
            capture: { _ in image }, selfProcessID: 999)
        defer { controller.stop() }
        controller.start(observesPrivacy: false)
        let view = WindowThumbnailImageView(frame: CGRect(x: 0, y: 0, width: 96, height: 60))
        controller.register(view, for: descriptor(1))
        for id in 1...40 { controller.request(descriptor(CGWindowID(id))) }
        try await settle { controller.retainedImageCount == WindowThumbnailController.maximumRetainedThumbnails }
        #expect(view.layer?.contents != nil)
        controller.release(descriptor(1))
        #expect(controller.retainedImageCount == WindowThumbnailController.maximumRetainedThumbnails - 1)
        #expect(view.layer?.contents == nil)
        controller.stop()
        #expect(controller.retainedImageCount == 0)
    }

    @Test func reopeningPickerRetainsRequestSlotsAndRejectsPreviousPresentationPixels() async throws {
        let image = try generatedImage()
        let probe = ThumbnailCaptureProbe()
        let controller = WindowThumbnailController(permissionGranted: { true }, identityIsCurrent: { _ in true },
            capture: probe.capture, selfProcessID: 999)
        defer { controller.stop(); probe.completeAll(with: nil) }
        controller.start(observesPrivacy: false)
        controller.request(descriptor(1))
        controller.request(descriptor(2))
        try await settle { probe.started.count == 2 }

        controller.stop()
        controller.start(observesPrivacy: false)
        let reopenedView = WindowThumbnailImageView(frame: CGRect(x: 0, y: 0, width: 96, height: 60))
        controller.register(reopenedView, for: descriptor(1))
        controller.request(descriptor(1))
        controller.request(descriptor(3))
        #expect(controller.activeRequestCount == 2)
        #expect(probe.started.count == 2, "Reopening must wait for previous uncancellable screenshots")

        probe.completeNext(with: image)
        try await settle { probe.started.count == 3 }
        #expect(controller.retainedImageCount == 0)
        #expect(reopenedView.layer?.contents == nil, "The previous presentation's image must not appear")
        probe.completeNext(with: image)
        try await settle { probe.started.count == 4 }
        #expect(controller.retainedImageCount == 0)
        #expect(reopenedView.layer?.contents == nil)
        #expect(probe.maximumActive == WindowThumbnailController.maximumConcurrentRequests)

        probe.completeAll(with: image)
        try await settle { controller.retainedImageCount == 2 && controller.activeRequestCount == 0 }
        #expect(reopenedView.layer?.contents != nil, "The reopened presentation can publish fresh pixels")
        controller.stop()
        #expect(reopenedView.layer?.contents == nil)
    }

    private func descriptor(_ id: CGWindowID, ownerPID: pid_t = 321) -> WindowDescriptor {
        WindowDescriptor(id: id, ownerPID: ownerPID, ownerBundleIdentifier: "test.generated.thumbnail",
                         bounds: CGRect(x: 0, y: 0, width: 640, height: 400))
    }

    private func generatedImage() throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 16, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 10))
        return try #require(context.makeImage())
    }

    private func settle(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(condition())
    }
}

@MainActor
private final class ThumbnailEnvironmentProbe {
    var permitted = true
    var currentPID: pid_t = 321
}

@MainActor
private final class ThumbnailCaptureProbe {
    private(set) var started: [WindowDescriptor] = []
    private var pending: [CheckedContinuation<CGImage?, Never>] = []
    private var active = 0
    private(set) var maximumActive = 0

    func capture(_ descriptor: WindowDescriptor) async -> CGImage? {
        started.append(descriptor)
        active += 1
        maximumActive = max(maximumActive, active)
        let result = await withCheckedContinuation { pending.append($0) }
        active -= 1
        return result
    }

    func completeNext(with image: CGImage?) {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume(returning: image)
    }

    func completeAll(with image: CGImage?) {
        let completions = pending
        pending.removeAll()
        for completion in completions { completion.resume(returning: image) }
    }
}
