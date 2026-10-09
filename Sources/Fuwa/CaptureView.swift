import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import FuwaCore
import ScreenCaptureKit
import VideoToolbox

enum FrameReceipt: Sendable {
    case firstCompleteFrame
    case completeFrame
}

enum FrozenFrameError: LocalizedError {
    case noCompleteFrame
    case imageConversionFailed(OSStatus)
    case invalidPixelDimensions
    case bitmapContextCreationFailed
    case bitmapImageCreationFailed

    var errorDescription: String? {
        switch self {
        case .noCompleteFrame:
            "尚未收到可以冻结的完整画面。"
        case .imageConversionFailed(let status):
            "无法读取最后一帧（VideoToolbox \(status)）。"
        case .invalidPixelDimensions:
            "最后一帧的尺寸无效。"
        case .bitmapContextCreationFailed, .bitmapImageCreationFailed:
            "无法创建冻结画面。"
        }
    }
}

@MainActor
final class CaptureView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let frozenLayer = CALayer()
    private var latestCompletePixelBuffer: CVPixelBuffer?
    private var hasReceivedCompleteFrame = false
    private var firstFrameBridgeLifecycle = FirstFrameBridgeLifecycle()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        guard let layer else { return }
        layer.backgroundColor = NSColor.clear.cgColor
        layer.masksToBounds = true

        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.clear.cgColor
        displayLayer.isHidden = true
        layer.addSublayer(displayLayer)

        frozenLayer.backgroundColor = NSColor.clear.cgColor
        frozenLayer.contentsGravity = .resizeAspect
        frozenLayer.magnificationFilter = .linear
        frozenLayer.minificationFilter = .trilinear
        frozenLayer.isHidden = true
        layer.addSublayer(frozenLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        frozenLayer.frame = bounds
        CATransaction.commit()
    }

    func consume(_ sampleBuffer: CMSampleBuffer) -> FrameReceipt? {
        guard Self.isCompleteFrame(sampleBuffer) else { return nil }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        guard CVPixelBufferGetWidth(pixelBuffer) > 0, CVPixelBufferGetHeight(pixelBuffer) > 0 else {
            return nil
        }

        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
            renderer.flush()
        }

        latestCompletePixelBuffer = pixelBuffer
        let isFirstCompleteFrame = !hasReceivedCompleteFrame
        let receipt: FrameReceipt = isFirstCompleteFrame
            ? .firstCompleteFrame
            : .completeFrame
        hasReceivedCompleteFrame = true

        renderer.enqueue(sampleBuffer)
        if isFirstCompleteFrame {
            firstFrameBridgeLifecycle.begin()
            setShowingFirstFrameBridge(Self.transientImage(from: pixelBuffer))
        } else if firstFrameBridgeLifecycle.receiveSubsequentCompleteFrame() {
            setShowingLiveFrame()
        }
        return receipt
    }

    static func sourcePointScale(_ sampleBuffer: CMSampleBuffer) -> CGFloat? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer, createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let value = attachments.first?[.scaleFactor] as? NSNumber else { return nil }
        let scale = CGFloat(value.doubleValue)
        guard scale.isFinite, (1...4).contains(scale) else { return nil }
        return scale
    }

    func makeFrozenImage(maxPixels: Int? = CaptureQuality.default.maximumPixelCount) throws -> CGImage {
        guard let pixelBuffer = latestCompletePixelBuffer else {
            throw FrozenFrameError.noCompleteFrame
        }

        var convertedImage: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(
            pixelBuffer,
            options: nil,
            imageOut: &convertedImage
        )
        guard status == noErr, let convertedImage else {
            throw FrozenFrameError.imageConversionFailed(status)
        }

        guard let dimensions = FrozenFrameSizing.fittedDimensions(
            sourceWidth: convertedImage.width,
            sourceHeight: convertedImage.height,
            maxPixels: maxPixels
        ) else {
            throw FrozenFrameError.invalidPixelDimensions
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw FrozenFrameError.bitmapContextCreationFailed
        }

        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil,
            width: dimensions.width,
            height: dimensions.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw FrozenFrameError.bitmapContextCreationFailed
        }

        context.setBlendMode(.copy)
        context.interpolationQuality = dimensions.width == convertedImage.width
            && dimensions.height == convertedImage.height
            ? .none
            : .high
        context.draw(
            convertedImage,
            in: CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height)
        )

        guard let independentImage = context.makeImage() else {
            throw FrozenFrameError.bitmapImageCreationFailed
        }
        return independentImage
    }

    func presentFrozen(_ image: CGImage) {
        latestCompletePixelBuffer = nil
        resetFirstPresentationState()
        displayLayer.sampleBufferRenderer.flush(
            removingDisplayedImage: true,
            completionHandler: nil
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frozenLayer.contents = image
        frozenLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        frozenLayer.isHidden = false
        displayLayer.isHidden = true
        CATransaction.commit()
    }

    func prepareForResumeKeepingFrozenImage() {
        latestCompletePixelBuffer = nil
        hasReceivedCompleteFrame = false
        resetFirstPresentationState()
        displayLayer.sampleBufferRenderer.flush(
            removingDisplayedImage: true,
            completionHandler: nil
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.isHidden = true
        frozenLayer.isHidden = frozenLayer.contents == nil
        CATransaction.commit()
    }

    func clearAllPixels() {
        latestCompletePixelBuffer = nil
        hasReceivedCompleteFrame = false
        resetFirstPresentationState()
        displayLayer.sampleBufferRenderer.flush(
            removingDisplayedImage: true,
            completionHandler: nil
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.isHidden = true
        frozenLayer.contents = nil
        frozenLayer.isHidden = true
        CATransaction.commit()
    }

    /// Called only after the panel has been ordered front and another main-run-
    /// loop turn has completed. The bridge remains until a subsequent complete
    /// frame is also available, so the renderer always has a real frame behind it.
    func completeFirstPresentation() {
        if firstFrameBridgeLifecycle.completeFirstPresentation() {
            setShowingLiveFrame()
        }
    }

    private func setShowingLiveFrame() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.isHidden = false
        frozenLayer.contents = nil
        frozenLayer.isHidden = true
        CATransaction.commit()
    }

    /// Display-layer rendering is asynchronous: revealing an empty layer
    /// immediately can flash transparent on initial pin and Resume. A lightweight
    /// CGImage of the same first complete frame stays above the renderer until a
    /// later complete frame proves the live layer has had time to present.
    private func setShowingFirstFrameBridge(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.isHidden = false
        if let image {
            frozenLayer.contents = image
            frozenLayer.contentsScale = window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 2
        }
        frozenLayer.isHidden = frozenLayer.contents == nil
        CATransaction.commit()
    }

    private func resetFirstPresentationState() {
        firstFrameBridgeLifecycle.reset()
    }

    private static func transientImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        var image: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(
            pixelBuffer,
            options: nil,
            imageOut: &image
        ) == noErr else {
            return nil
        }
        return image
    }

    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return false }
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? NSNumber,
            SCFrameStatus(rawValue: rawStatus.intValue) == .complete
        else {
            return false
        }
        return true
    }
}
