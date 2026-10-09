import AppKit
import FuwaCore

/// A local image-selection window. It never sends input to the captured app.
@MainActor
final class CaptureRegionSelectionPanel: NSPanel, NSWindowDelegate {
    private var onSelection: ((NormalizedCaptureRegion) -> Void)?
    private var onCancellation: (() -> Void)?
    private let selectionView: CaptureRegionSelectionView

    init(image: CGImage, previousRegion: NormalizedCaptureRegion?, sourceFrame: CGRect,
         copy: FuwaCopy, onSelection: @escaping (NormalizedCaptureRegion) -> Void,
         onCancellation: @escaping () -> Void) {
        selectionView = CaptureRegionSelectionView(image: image, previousRegion: previousRegion)
        self.onSelection = onSelection
        self.onCancellation = onCancellation
        let visible = NSScreen.screens.first(where: { $0.frame.intersects(sourceFrame) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let size = CGSize(width: min(900, visible.width * 0.8), height: min(680, visible.height * 0.8))
        super.init(contentRect: CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                      width: size.width, height: size.height),
                   styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = copy.text(.chooseArea)
        level = .floating
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        sharingType = .none
        collectionBehavior = [.canJoinAllApplications, .fullScreenAuxiliary]
        minSize = CGSize(width: 420, height: 300)
        delegate = self
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        selectionView.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height - 58)
        selectionView.autoresizingMask = [.width, .height]
        container.addSubview(selectionView)
        let instruction = NSTextField(wrappingLabelWithString: copy.text(.cropInstructions))
        instruction.font = .systemFont(ofSize: 12)
        instruction.textColor = .secondaryLabelColor
        instruction.frame = CGRect(x: 16, y: size.height - 49, width: size.width - 124, height: 40)
        instruction.autoresizingMask = [.width, .minYMargin]
        container.addSubview(instruction)
        let cancel = NSButton(title: copy.text(.cancel), target: self, action: #selector(cancelSelection))
        cancel.bezelStyle = .rounded
        cancel.frame = CGRect(x: size.width - 100, y: size.height - 44, width: 84, height: 28)
        cancel.autoresizingMask = [.minXMargin, .minYMargin]
        cancel.keyEquivalent = "\u{1b}"
        container.addSubview(cancel)
        contentView = container
        selectionView.onSelection = { [weak self] region in
            guard let self else { return }
            let action = self.onSelection
            self.onSelection = nil
            self.onCancellation = nil
            self.close()
            action?(region)
        }
    }

    override var canBecomeKey: Bool { true }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func cancelSelection() { close() }

    override func cancelOperation(_ sender: Any?) { close() }

    func windowWillClose(_ notification: Notification) {
        let action = onCancellation
        onSelection = nil
        onCancellation = nil
        selectionView.onSelection = nil
        action?()
    }

    /// Teardown suppresses callbacks so closing cannot reconfigure a stopped pin.
    func dismissForTeardown() {
        onSelection = nil
        onCancellation = nil
        selectionView.onSelection = nil
        close()
    }
}

@MainActor
private final class CaptureRegionSelectionView: NSView {
    let image: CGImage
    let previousRegion: NormalizedCaptureRegion?
    var onSelection: ((NormalizedCaptureRegion) -> Void)?
    private var startPoint: NSPoint?
    private var selection = CGRect.zero

    init(image: CGImage, previousRegion: NormalizedCaptureRegion?) {
        self.image = image
        self.previousRegion = previousRegion
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var imageRect: CGRect {
        CaptureReferenceGeometry.aspectFit(imageSize: CGSize(width: image.width, height: image.height),
                                           in: bounds.insetBy(dx: 12, dy: 12))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSGraphicsContext.current?.cgContext.draw(image, in: imageRect)
        guard startPoint != nil, selection.width > 0, selection.height > 0 else { return }
        let shade = NSBezierPath(rect: imageRect)
        shade.appendRect(selection.intersection(imageRect))
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.5).setFill()
        shade.fill()
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection.intersection(imageRect).insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(point) else { return }
        startPoint = point
        selection = CGRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(startPoint.x, point.x), y: min(startPoint.y, point.y),
                           width: abs(point.x - startPoint.x), height: abs(point.y - startPoint.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard startPoint != nil else { return }
        mouseDragged(with: event)
        let region = CaptureReferenceGeometry.selectedRegion(selection: selection, imageRect: imageRect,
                                                            within: previousRegion)
        startPoint = nil
        needsDisplay = true
        if let region { onSelection?(region) }
    }

    override func resetCursorRects() { addCursorRect(imageRect, cursor: .crosshair) }
}
