import AppKit
import CoreMedia
import CoreVideo
import FuwaCore
import ScreenCaptureKit
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct ReferenceCaptureWorkflowTests {
    @Test func cropUsesSourcePointsAndPreservesRetinaPixels() {
        let region = NormalizedCaptureRegion(x: 0.25, y: 0.1, width: 0.5, height: 0.3)
        let native = PinSession.makeConfiguration(pointSize: CGSize(width: 1200, height: 800), pointScale: 2,
                                                 captureRegion: region, frameRate: .sixty)
        #expect(abs(native.sourceRect.minX - 300) < 0.000001)
        #expect(abs(native.sourceRect.minY - 80) < 0.000001)
        #expect(abs(native.sourceRect.width - 600) < 0.000001)
        #expect(abs(native.sourceRect.height - 240) < 0.000001)
        #expect(native.width == 1200 && native.height == 480)
        #expect(native.minimumFrameInterval == CMTime(value: 1, timescale: 60))
        let reduced = PinSession.makeConfiguration(pointSize: CGSize(width: 1200, height: 800), pointScale: 1,
                                                  captureQuality: CaptureQuality(percentage: 50)!,
                                                  captureRegion: region, frameRate: .one)
        #expect(reduced.width == 300 && reduced.height == 120)
        #expect(reduced.sourceRect == native.sourceRect)
        #expect(reduced.minimumFrameInterval == CMTime(value: 1, timescale: 1))
        let genuinelyFractional = PinSession.makeConfiguration(
            pointSize: CGSize(width: 100, height: 100), pointScale: 2,
            captureRegion: NormalizedCaptureRegion(x: 0, y: 0, width: 0.301, height: 0.301)
        )
        #expect(genuinelyFractional.width == 61 && genuinelyFractional.height == 61)
    }

    @Test func selectionAccountsForLetterboxAndAppKitYAxis() throws {
        let imageRect = CaptureReferenceGeometry.aspectFit(imageSize: CGSize(width: 1000, height: 500),
                                                           in: CGRect(x: 0, y: 0, width: 600, height: 600))
        #expect(imageRect == CGRect(x: 0, y: 150, width: 600, height: 300))
        let first = try #require(CaptureReferenceGeometry.selectedRegion(
            selection: CGRect(x: 150, y: 300, width: 300, height: 150), imageRect: imageRect, within: nil
        ))
        #expect(first == NormalizedCaptureRegion(x: 0.25, y: 0, width: 0.5, height: 0.5))
        let second = try #require(CaptureReferenceGeometry.selectedRegion(
            selection: CGRect(x: 0, y: 150, width: 300, height: 150), imageRect: imageRect, within: first
        ))
        #expect(second == NormalizedCaptureRegion(x: 0.25, y: 0.25, width: 0.25, height: 0.25))
        #expect(CaptureReferenceGeometry.selectedRegion(selection: CGRect(x: 0, y: 0, width: 600, height: 100),
                                                        imageRect: imageRect, within: nil) == nil)
    }

    @Test func malformedCropIsClampedOrRejected() {
        #expect(CaptureReferenceGeometry.sanitized(NormalizedCaptureRegion(x: .nan, y: 0, width: 1, height: 1)) == nil)
        #expect(CaptureReferenceGeometry.sanitized(NormalizedCaptureRegion(x: 0, y: 0, width: -1, height: 1)) == nil)
        #expect(CaptureReferenceGeometry.sanitized(NormalizedCaptureRegion(x: 2, y: 0, width: 1, height: 1)) == nil)
        #expect(CaptureReferenceGeometry.sanitized(NormalizedCaptureRegion(x: -0.2, y: 0.5, width: 0.5, height: 1))
                == NormalizedCaptureRegion(x: 0, y: 0.5, width: 0.3, height: 0.5))
    }

    @Test func independentResizeKeepsAspectAndTopLeftCorner() {
        let original = CGRect(x: -700, y: 400, width: 600, height: 300)
        let resized = CaptureReferenceGeometry.resizedFrame(original, requestedWidth: 320,
                                                           aspect: CGSize(width: 1000, height: 500))
        #expect(resized == CGRect(x: -700, y: 540, width: 320, height: 160))
        let tiny = CaptureReferenceGeometry.resizedFrame(original, requestedWidth: 1,
                                                        aspect: CGSize(width: 1000, height: 500))
        #expect(tiny.width >= 96 && tiny.height >= 64)
        #expect(tiny.minX == original.minX && tiny.maxY == original.maxY)
        for aspect in [CGSize(width: 5000, height: 3), CGSize(width: 3, height: 5000)] {
            let thin = CaptureReferenceGeometry.resizedFrame(original, requestedWidth: 600, aspect: aspect,
                                                            maximumSize: CGSize(width: 900, height: 650))
            #expect(thin.width <= 900 && thin.height <= 650)
            #expect(thin.width >= 96 && thin.height >= 64)
            let picture = CaptureReferenceGeometry.aspectFit(imageSize: aspect, in: thin)
            #expect(abs(picture.width / picture.height - aspect.width / aspect.height) < 0.00001)
            #expect(thin.minX == original.minX && thin.maxY == original.maxY)
        }
        let narrower = CaptureReferenceGeometry.resizedFrame(original, requestedWidth: 320,
            aspect: CGSize(width: 5000, height: 3), maximumSize: CGSize(width: 900, height: 650))
        #expect(narrower.width == 320 && narrower.height == 64)
    }

    @Test func tallReferenceCanShrinkAtMinimumWidthAndKeepItsSizeOnReconciliation() {
        let aspect = CGSize(width: 3, height: 5000)
        let limit = CGSize(width: 900, height: 650)
        let initial = CaptureReferenceGeometry.resizedFrame(
            CGRect(x: -700, y: 400, width: 600, height: 300), requestedWidth: 600,
            aspect: aspect, maximumSize: limit
        )
        #expect(initial.width == 96 && initial.height == 300)

        // The corner handle maps a 150 pt upward drag through the outer frame's
        // ratio. Width stays operable while the picture's displayed height shrinks.
        let requestedWidth = initial.width - 150 / (initial.height / initial.width)
        let smaller = CaptureReferenceGeometry.resizedFrame(
            initial, requestedWidth: requestedWidth, aspect: aspect, maximumSize: limit
        )
        #expect(smaller.width == 96 && smaller.height == 150)
        #expect(smaller.minX == initial.minX && smaller.maxY == initial.maxY)
        let reconciled = CaptureReferenceGeometry.resizedFrame(
            smaller, requestedWidth: smaller.width, aspect: aspect, maximumSize: limit
        )
        #expect(reconciled == smaller)

        let smallest = CaptureReferenceGeometry.resizedFrame(
            smaller, requestedWidth: -100, aspect: aspect, maximumSize: limit
        )
        #expect(smallest.width == 96 && smallest.height == 64)
        let largest = CaptureReferenceGeometry.resizedFrame(
            smaller, requestedWidth: 2000, aspect: aspect, maximumSize: limit
        )
        #expect(largest.width == 96 && largest.height == limit.height)
        let picture = CaptureReferenceGeometry.aspectFit(imageSize: aspect, in: smaller)
        #expect(abs(picture.width / picture.height - aspect.width / aspect.height) < 0.00001)
        #expect(picture.width <= smaller.width && picture.height <= smaller.height)
    }

    @Test func thinImageCanStillSelectItsCompleteHeight() throws {
        let imageRect = CGRect(x: 0, y: 150, width: 600, height: 0.5)
        let selection = try #require(CaptureReferenceGeometry.selectedRegion(
            selection: CGRect(x: 150, y: 149, width: 300, height: 4), imageRect: imageRect, within: nil
        ))
        #expect(selection == NormalizedCaptureRegion(x: 0.25, y: 0, width: 0.5, height: 1))
    }

    @Test func restoringLivePictureCannotChooseFromTheOldFrame() {
        var restored = PinSnapshot(id: UUID(), sourceWindowID: 100, applicationName: "Reference",
            bundleIdentifier: nil, windowTitle: "Progress", state: .live, errorMessage: nil)
        #expect(restored.canChooseArea)
        restored.isAwaitingFreshFrame = true
        #expect(!restored.canChooseArea)
        restored.isAwaitingFreshFrame = false
        #expect(restored.canChooseArea)
    }

    @Test func referenceStatusDoesNotBlockDragAndContextMenuKeepsPictureOptionsReachable() throws {
        _ = NSApplication.shared
        let view = CaptureView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        defer { view.clearAllPixels() }
        view.setIdleIndicator(title: "Picture unchanged", explanation: "Check the source app.")
        view.layoutSubtreeIfNeeded()
        let badge = try #require(view.subviews.first)
        let hitPoint = CGPoint(x: badge.frame.midX, y: badge.frame.midY)
        #expect(badge.hitTest(hitPoint) == nil)
        #expect(view.hitTest(hitPoint) === view)
        #expect(view.resizeHandleRect == CGRect(x: 296, y: 0, width: 24, height: 24))
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        var requestedControls = false
        view.onRequestControls = { requestedControls = true }
        view.controlsTitle = "Picture Options"
        #expect(view.menu(for: event) == nil)
        view.isReferencePresentation = true
        let menu = try #require(view.menu(for: event))
        #expect(menu.items.count == 1 && menu.items[0].title == "Picture Options")
        menu.performActionForItem(at: 0)
        #expect(requestedControls)
    }

    @Test func idleDependsOnPictureChangesAndRecoversChosenRate() {
        var activity = CapturedPictureActivity(idleDelay: 15)
        let size = PixelDimensions(width: 1920, height: 1080)
        let initialChange = activity.observe(samples: [0, 0, 0], dimensions: size, at: 0)
        #expect(initialChange)
        // Complete frames can continue arriving with identical content.
        for second in 1..<15 {
            let changed = activity.observe(samples: [0, 0, 0], dimensions: size, at: Double(second))
            #expect(!changed)
        }
        #expect(!activity.isIdle)
        let becameIdle = activity.evaluate(at: 15)
        #expect(becameIdle)
        #expect(activity.isIdle)
        let activityResumed = activity.observe(samples: [20, 0, 0], dimensions: size, at: 16)
        #expect(activityResumed)
        #expect(!activity.isIdle)
        let earlyEvaluation = activity.evaluate(at: 30)
        let laterEvaluation = activity.evaluate(at: 31)
        #expect(!earlyEvaluation)
        #expect(laterEvaluation)
        activity.reset()
        #expect(!activity.isIdle)
        let evaluationAfterReset = activity.evaluate(at: 100)
        #expect(!evaluationAfterReset)
    }

    @Test func gradualChangesAccumulateAgainstSignificantPicture() {
        var activity = CapturedPictureActivity()
        let size = PixelDimensions(width: 10, height: 10)
        let initialChange = activity.observe(samples: [0, 0, 0], dimensions: size, at: 0)
        let smallChange = activity.observe(samples: [4, 0, 0], dimensions: size, at: 10)
        let accumulatedChange = activity.observe(samples: [8, 0, 0], dimensions: size, at: 14)
        let prematureIdle = activity.evaluate(at: 15)
        #expect(initialChange)
        #expect(!smallChange)
        #expect(accumulatedChange)
        #expect(!prematureIdle)
        #expect(!activity.isIdle)
        let dimensionChange = activity.observe(samples: [8, 0, 0], dimensions: PixelDimensions(width: 20, height: 10), at: 20)
        let afterDimensionChange = activity.evaluate(at: 30)
        #expect(dimensionChange)
        #expect(!afterDimensionChange)
    }

    @Test func laterHideAndPrivacyStopInvalidateAsyncRestoration() {
        var visibility = CapturePresentationSuppression()
        _ = visibility.change(to: true)
        let firstRestore = visibility.change(to: false)
        #expect(visibility.allowsRestore(revision: firstRestore))
        _ = visibility.change(to: true)
        #expect(!visibility.allowsRestore(revision: firstRestore))
        let secondRestore = visibility.change(to: false)
        #expect(visibility.allowsRestore(revision: secondRestore))
        visibility.stop()
        #expect(!visibility.allowsRestore(revision: secondRestore))
        let accidentalRestoreAfterStop = visibility.change(to: false)
        #expect(!visibility.allowsRestore(revision: accidentalRestoreAfterStop))
    }

    @Test func realPixelSignatureIsBoundedAndRetainedFrameCanPauseWhileHidden() throws {
        _ = NSApplication.shared
        let sample = try makeSample(width: 1920, height: 1080, value: 20)
        let view = CaptureView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        defer { view.clearAllPixels() }
        #expect(view.consume(sample) != nil)
        let signature = try #require(view.activitySamples())
        #expect(signature.samples.count == 24 * 18 * 3)
        #expect(signature.samples.allSatisfy { $0 == 20 })
        #expect(signature.dimensions == PixelDimensions(width: 1920, height: 1080))
        let independentFrame = try view.makeFrozenImage()
        view.presentFrozen(independentFrame)
        #expect(view.activitySamples() == nil)
        let retained = try view.makeFrozenImage()
        #expect(retained.width == 1920 && retained.height == 1080)
        // Restoration may fail or its source may close before the first new
        // complete frame. The independent last image remains available.
        view.prepareForResumeKeepingFrozenImage()
        let afterFailedRestore = try view.makeFrozenImage()
        #expect(afterFailedRestore.width == 1920 && afterFailedRestore.height == 1080)
        view.clearAllPixels()
        #expect(throws: FrozenFrameError.self) { try view.makeFrozenImage() }
    }

    @Test func cropChooserConstructionDoesNotRevealPixelsAndTeardownDoesNotCommit() {
        _ = NSApplication.shared
        let context = CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var selected = false, canceled = false
        let chooser = CaptureRegionSelectionPanel(image: context.makeImage()!, previousRegion: nil,
            sourceFrame: CGRect(x: 10, y: 10, width: 100, height: 100), copy: FuwaCopy(language: .english),
            onSelection: { _ in selected = true }, onCancellation: { canceled = true })
        #expect(!chooser.isVisible)
        #expect(chooser.sharingType == .none)
        let selection = chooser.contentView!.subviews[0]
        let before = Mirror(reflecting: selection).descendant("image")!
        #expect(!Mirror(reflecting: before).children.isEmpty)
        chooser.dismissForTeardown()
        let after = Mirror(reflecting: selection).descendant("image")!
        #expect(Mirror(reflecting: after).children.isEmpty)
        #expect(!selected && !canceled)
    }

    @Test func nativeCropDragCommitsTopRightQuarterAndClearsPreview() throws {
        _ = NSApplication.shared
        let context = try #require(CGContext(data: nil, width: 1000, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        var selected: NormalizedCaptureRegion?
        let chooser = CaptureRegionSelectionPanel(image: try #require(context.makeImage()), previousRegion: nil,
            sourceFrame: CGRect(x: 10, y: 10, width: 100, height: 100), copy: FuwaCopy(language: .english),
            onSelection: { selected = $0 }, onCancellation: {})
        defer { chooser.dismissForTeardown() }
        let content = try #require(chooser.contentView)
        content.layoutSubtreeIfNeeded()
        let selection = try #require(content.subviews.first)
        let imageRect = CaptureReferenceGeometry.aspectFit(imageSize: CGSize(width: 1000, height: 500),
            in: selection.bounds.insetBy(dx: 12, dy: 12))
        let startPoint = CGPoint(x: imageRect.midX, y: imageRect.maxY)
        let endPoint = CGPoint(x: imageRect.maxX, y: imageRect.midY)
        func event(_ type: NSEvent.EventType, point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: selection.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: chooser.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))
        }
        // CGRect.contains excludes maxY; begin just inside the visible image.
        let insetStart = CGPoint(x: startPoint.x, y: startPoint.y - 0.01)
        selection.mouseDown(with: try event(.leftMouseDown, point: insetStart))
        selection.mouseDragged(with: try event(.leftMouseDragged, point: endPoint))
        selection.mouseUp(with: try event(.leftMouseUp, point: endPoint))
        let region = try #require(selected)
        #expect(abs(region.x - 0.5) < 0.0001 && abs(region.y) < 0.0001)
        #expect(abs(region.width - 0.5) < 0.0001 && abs(region.height - 0.5) < 0.0001)
        let retainedImage = try #require(Mirror(reflecting: selection).descendant("image"))
        #expect(Mirror(reflecting: retainedImage).children.isEmpty)
        #expect(!chooser.isVisible)
    }

    @Test func narrowCropInstructionsStayAboveImageInEveryLanguage() throws {
        let context = try #require(CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for language in FuwaLanguage.allCases {
            let chooser = CaptureRegionSelectionPanel(image: try #require(context.makeImage()), previousRegion: nil,
                sourceFrame: CGRect(x: 10, y: 10, width: 100, height: 100), copy: FuwaCopy(language: language),
                onSelection: { _ in }, onCancellation: {})
            defer { chooser.dismissForTeardown() }
            chooser.minSize = .zero
            chooser.setContentSize(CGSize(width: 320, height: 280))
            let content = try #require(chooser.contentView)
            content.layoutSubtreeIfNeeded()
            let selection = try #require(content.subviews.first)
            let instruction = try #require(content.subviews.compactMap { $0 as? NSTextField }.first)
            let cancel = try #require(content.subviews.compactMap { $0 as? NSButton }.first)
            #expect(instruction.frame.minY > selection.frame.maxY)
            #expect(instruction.frame.maxY <= content.bounds.maxY)
            #expect(instruction.frame.maxX < cancel.frame.minX)
            #expect(cancel.frame.maxX <= content.bounds.maxX)
            #expect(instruction.frame.height >= 16)
        }
    }

    private func makeSample(width: Int, height: Int, value: UInt8) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer) == kCVReturnSuccess)
        let pixels = try #require(pixelBuffer)
        #expect(CVPixelBufferLockBaseAddress(pixels, []) == kCVReturnSuccess)
        if let base = CVPixelBufferGetBaseAddress(pixels) {
            memset(base, Int32(value), CVPixelBufferGetBytesPerRow(pixels) * height)
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        var format: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels, formatDescriptionOut: &format) == noErr)
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixels,
            formatDescription: try #require(format), sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        let buffer = try #require(sample)
        let attachments = try #require(CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true))
        let metadata = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: NSMutableDictionary.self)
        metadata[SCStreamFrameInfo.status.rawValue] = SCFrameStatus.complete.rawValue
        return buffer
    }
}
