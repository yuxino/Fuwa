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
    case bitmapContextCreationFailed
    case bitmapImageCreationFailed

    var errorDescription: String? {
        switch self {
        case .noCompleteFrame:
            "尚未收到可以暂停的完整画面。"
        case .imageConversionFailed(let status):
            "无法读取最后一帧（VideoToolbox \(status)）。"
        case .bitmapContextCreationFailed, .bitmapImageCreationFailed:
            "无法保留当前画面。"
        }
    }
}

@MainActor
final class CaptureView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let frozenLayer = CALayer()
    private let referenceBorderLayer = CAShapeLayer()
    private let referenceHandleBackgroundLayer = CAShapeLayer()
    private let referenceHandleLayer = CAShapeLayer()
    private let idleIndicator = CapturePassiveStatusLabel(labelWithString: "")
    private var retainedImage: CGImage?
    private var latestCompletePixelBuffer: CVPixelBuffer?
    private var hasReceivedCompleteFrame = false
    private var firstFrameBridgeLifecycle = FirstFrameBridgeLifecycle()
    var isReferencePresentation = false {
        didSet {
            referenceHandleLayer.isHidden = !isReferencePresentation
            referenceHandleBackgroundLayer.isHidden = !isReferencePresentation
            referenceBorderLayer.isHidden = !isReferencePresentation
            layer?.backgroundColor = isReferencePresentation ? NSColor.windowBackgroundColor.cgColor : NSColor.clear.cgColor
            window?.invalidateCursorRects(for: self)
            needsLayout = true
        }
    }
    var referenceAspect = CGSize(width: 1, height: 1)
    var onReferenceFrameChanged: (() -> Void)?
    var onRequestControls: (() -> Void)?
    var controlsTitle = ""
    private var resizeStart: (location: NSPoint, frame: NSRect)?

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
        referenceBorderLayer.fillColor = nil
        referenceBorderLayer.strokeColor = NSColor.separatorColor.cgColor
        referenceBorderLayer.lineWidth = 1
        referenceBorderLayer.isHidden = true
        layer.addSublayer(referenceBorderLayer)
        referenceHandleBackgroundLayer.fillColor = NSColor.black.withAlphaComponent(0.64).cgColor
        referenceHandleBackgroundLayer.isHidden = true
        layer.addSublayer(referenceHandleBackgroundLayer)
        referenceHandleLayer.fillColor = nil
        referenceHandleLayer.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        referenceHandleLayer.lineWidth = 2
        referenceHandleLayer.shadowColor = NSColor.black.cgColor
        referenceHandleLayer.shadowOpacity = 0
        referenceHandleLayer.shadowRadius = 1
        referenceHandleLayer.shadowOffset = .zero
        referenceHandleLayer.isHidden = true
        layer.addSublayer(referenceHandleLayer)
        idleIndicator.font = .systemFont(ofSize: 11, weight: .medium)
        idleIndicator.textColor = .black
        idleIndicator.backgroundColor = NSColor.white.withAlphaComponent(0.94)
        idleIndicator.drawsBackground = true
        idleIndicator.lineBreakMode = .byTruncatingTail
        idleIndicator.maximumNumberOfLines = 1
        idleIndicator.isHidden = true
        idleIndicator.wantsLayer = true
        idleIndicator.layer?.cornerRadius = 3
        idleIndicator.layer?.masksToBounds = true
        addSubview(idleIndicator)
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
        referenceBorderLayer.frame = bounds
        referenceBorderLayer.path = CGPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5), transform: nil)
        referenceHandleBackgroundLayer.frame = bounds
        referenceHandleBackgroundLayer.path = CGPath(roundedRect: resizeHandleRect.insetBy(dx: 2, dy: 2),
                                                      cornerWidth: 3, cornerHeight: 3, transform: nil)
        referenceHandleLayer.frame = bounds
        let path = CGMutablePath()
        for offset in [CGFloat(4), 9, 14] {
            path.move(to: CGPoint(x: bounds.maxX - offset - 2, y: 3))
            path.addLine(to: CGPoint(x: bounds.maxX - 3, y: offset + 2))
        }
        referenceHandleLayer.path = path
        let width = min(max(0, bounds.width - 16), idleIndicator.intrinsicContentSize.width + 12)
        idleIndicator.frame = CGRect(x: 8, y: max(0, bounds.height - 28), width: width, height: 20)
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isReferencePresentation }

    var resizeHandleRect: CGRect {
        CGRect(x: max(bounds.minX, bounds.maxX - 24), y: bounds.minY,
               width: min(24, bounds.width), height: min(24, bounds.height))
    }

    override func resetCursorRects() {
        guard isReferencePresentation else { return }
        addCursorRect(bounds, cursor: .openHand)
        let resizeCursor: NSCursor
        if #available(macOS 15, *) { resizeCursor = .frameResize(position: .bottomRight, directions: .all) }
        else { resizeCursor = .resizeLeftRight }
        addCursorRect(resizeHandleRect, cursor: resizeCursor)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard isReferencePresentation, onRequestControls != nil else { return nil }
        let menu = NSMenu()
        let controls = NSMenuItem(title: controlsTitle, action: #selector(requestControls), keyEquivalent: "")
        controls.target = self
        menu.addItem(controls)
        return menu
    }

    @objc private func requestControls() { onRequestControls?() }

    override func mouseDown(with event: NSEvent) {
        guard isReferencePresentation, let window else { return }
        if event.modifierFlags.contains(.control), let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if resizeHandleRect.contains(point) {
            resizeStart = (NSEvent.mouseLocation, window.frame)
        } else {
            NSCursor.closedHand.push()
            defer { NSCursor.pop() }
            window.performDrag(with: event)
            onReferenceFrameChanged?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let resizeStart, let window else { return }
        let pointer = NSEvent.mouseLocation
        let dx = pointer.x - resizeStart.location.x
        let dy = resizeStart.location.y - pointer.y
        let ratio = resizeStart.frame.height / max(1, resizeStart.frame.width)
        let delta = abs(dy) > abs(dx * ratio) ? dy / max(0.001, ratio) : dx
        window.setFrame(CaptureReferenceGeometry.resizedFrame(
            resizeStart.frame, requestedWidth: resizeStart.frame.width + delta, aspect: referenceAspect,
            maximumSize: window.screen?.visibleFrame.size
        ), display: true)
        onReferenceFrameChanged?()
    }

    override func mouseUp(with event: NSEvent) { resizeStart = nil }

    func setIdleIndicator(title: String?, explanation: String? = nil) {
        idleIndicator.stringValue = title ?? ""
        idleIndicator.toolTip = explanation
        idleIndicator.setAccessibilityLabel(title)
        idleIndicator.setAccessibilityHelp(explanation)
        idleIndicator.isHidden = title == nil
        needsLayout = true
    }

    /// At most 24 × 18 pixels are sampled, independent of window resolution.
    func activitySamples() -> (samples: [UInt8], dimensions: PixelDimensions)? {
        guard let pixels = latestCompletePixelBuffer,
              CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA else { return nil }
        guard CVPixelBufferLockBaseAddress(pixels, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return nil }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
        guard width > 0, height > 0, rowBytes >= width * 4 else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let columns = min(24, width), rows = min(18, height)
        var samples: [UInt8] = []
        samples.reserveCapacity(columns * rows * 3)
        for row in 0..<rows {
            let y = min(height - 1, (row * 2 + 1) * height / (rows * 2))
            for column in 0..<columns {
                let x = min(width - 1, (column * 2 + 1) * width / (columns * 2))
                let offset = y * rowBytes + x * 4
                samples.append(bytes[offset]); samples.append(bytes[offset + 1]); samples.append(bytes[offset + 2])
            }
        }
        return (samples, PixelDimensions(width: width, height: height))
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

    func makeFrozenImage() throws -> CGImage {
        guard let pixelBuffer = latestCompletePixelBuffer else {
            if let image = retainedImage { return image }
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

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw FrozenFrameError.bitmapContextCreationFailed
        }

        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil,
            width: convertedImage.width,
            height: convertedImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw FrozenFrameError.bitmapContextCreationFailed
        }

        context.setBlendMode(.copy)
        // Copy the received frame without reducing it a second time.
        context.interpolationQuality = .none
        context.draw(
            convertedImage,
            in: CGRect(x: 0, y: 0, width: convertedImage.width, height: convertedImage.height)
        )

        guard let independentImage = context.makeImage() else {
            throw FrozenFrameError.bitmapImageCreationFailed
        }
        return independentImage
    }

    func presentFrozen(_ image: CGImage) {
        retainedImage = image
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
        retainedImage = nil
        setIdleIndicator(title: nil)
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
        retainedImage = nil
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
            retainedImage = image
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

/// Status remains readable to accessibility and hover help without blocking drag.
@MainActor
private final class CapturePassiveStatusLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
