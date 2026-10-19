import AppKit
import CoreMedia
import FuwaCore

/// A second local renderer of the existing capture stream. It neither starts a
/// capture nor forwards input, and releases every retained pixel when dismissed.
@MainActor
final class ReferencePreviewController {
    let panel: NSPanel
    private let picture: CaptureView

    init(image: CGImage, frame: CGRect, collectionBehavior: NSWindow.CollectionBehavior) {
        picture = CaptureView(frame: CGRect(origin: .zero, size: frame.size))
        picture.autoresizingMask = [.width, .height]
        picture.presentFrozen(image)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.contentView = picture
        panel.level = .floating
        panel.collectionBehavior = collectionBehavior
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = true
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
    }

    func show() { panel.orderFrontRegardless() }

    func consume(_ sampleBuffer: CMSampleBuffer) {
        guard panel.isVisible else { return }
        if picture.consume(sampleBuffer) != nil { picture.completeFirstPresentation() }
    }

    func dismiss() {
        panel.orderOut(nil)
        picture.clearAllPixels()
        panel.contentView = nil
        panel.close()
    }
}
