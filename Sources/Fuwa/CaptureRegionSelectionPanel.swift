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
        let screens = NSScreen.screens
        let screenIndex = FloatingControlsLayout.screenIndex(source: sourceFrame, screens: screens.map(\.frame))
        let visible = screenIndex.map { screens[$0].visibleFrame }
            ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let style: NSWindow.StyleMask = [.titled, .closable, .resizable, .nonactivatingPanel]
        let available = NSWindow.contentRect(forFrameRect: visible.insetBy(dx: 16, dy: 16), styleMask: style)
        let size = CGSize(width: min(900, available.width * 0.9), height: min(680, available.height * 0.9))
        super.init(contentRect: CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2,
                                      width: size.width, height: size.height),
                   styleMask: style,
                   backing: .buffered, defer: false)
        title = copy.text(.chooseArea)
        level = .floating
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        sharingType = .none
        collectionBehavior = [.canJoinAllApplications, .fullScreenAuxiliary]
        minSize = CGSize(width: min(420, visible.width - 32), height: min(300, visible.height - 32))
        delegate = self
        let instruction = NSTextField(wrappingLabelWithString: copy.text(.cropInstructions))
        instruction.font = .systemFont(ofSize: 12)
        instruction.textColor = .secondaryLabelColor
        let cancel = NSButton(title: copy.text(.cancel), target: self, action: #selector(cancelSelection))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let container = CaptureRegionSelectionContentView(frame: CGRect(origin: .zero, size: size),
                                                          selectionView: selectionView, instruction: instruction,
                                                          cancelButton: cancel)
        contentView = container
        container.layoutSubtreeIfNeeded()
        selectionView.onSelection = { [weak self] region in
            guard let self else { return }
            let action = self.onSelection
            self.onSelection = nil
            self.onCancellation = nil
            self.selectionView.clearImage()
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
        selectionView.clearImage()
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
        selectionView.clearImage()
        close()
    }
}

/// Let required instructions wrap without covering the image when narrowed.
@MainActor
private final class CaptureRegionSelectionContentView: NSView {
    let selectionView: NSView
    let instruction: NSTextField
    let cancelButton: NSButton

    init(frame: CGRect, selectionView: NSView, instruction: NSTextField, cancelButton: NSButton) {
        self.selectionView = selectionView
        self.instruction = instruction
        self.cancelButton = cancelButton
        super.init(frame: frame)
        addSubview(selectionView)
        addSubview(instruction)
        addSubview(cancelButton)
        needsLayout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let buttonWidth = max(72, cancelButton.fittingSize.width)
        let textWidth = max(1, bounds.width - buttonWidth - 48)
        let font = instruction.font ?? .systemFont(ofSize: 12)
        let textHeight = ceil((instruction.stringValue as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]
        ).height) + 4
        let headerHeight = max(58, textHeight + 20)
        selectionView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - headerHeight))
        instruction.frame = CGRect(x: 16, y: bounds.height - 10 - textHeight, width: textWidth, height: textHeight)
        cancelButton.frame = CGRect(x: bounds.width - buttonWidth - 16,
                                    y: bounds.height - headerHeight / 2 - 14, width: buttonWidth, height: 28)
    }
}

@MainActor
private final class CaptureRegionSelectionView: NSView {
    private var image: CGImage?
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
        guard let image else { return .zero }
        return CaptureReferenceGeometry.aspectFit(imageSize: CGSize(width: image.width, height: image.height),
                                                  in: bounds.insetBy(dx: 12, dy: 12))
    }

    func clearImage() {
        image = nil
        startPoint = nil
        selection = .zero
        needsDisplay = true
        // A closed AppKit window can remain retained. Clear its backing surface
        // as well as the CGImage rather than relying on eventual deallocation.
        displayIfNeeded()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let image else { return }
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
