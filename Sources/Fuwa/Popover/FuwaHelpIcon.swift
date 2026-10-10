import AppKit
import SwiftUI

/// A neutral information image with passive hover help and no click action.
struct FuwaHelpIcon: View {
    let title: String
    let text: String

    var body: some View {
        FuwaHelpImageRepresentable(title: title, text: text)
            .frame(width: 24, height: 24)
            // Explanations remain readable while the related capture action is busy.
            .environment(\.isEnabled, true)
    }
}

@MainActor
private struct FuwaHelpImageRepresentable: NSViewRepresentable {
    let title: String
    let text: String

    func makeNSView(context: Context) -> FuwaHelpImageView {
        FuwaHelpImageView(title: title, text: text)
    }

    func updateNSView(_ view: FuwaHelpImageView, context: Context) {
        view.update(title: title, text: text)
    }
}

@MainActor
final class FuwaHelpImageView: NSImageView {
    private var helpTitle = ""
    private var helpText = ""
    private var hoverTask: Task<Void, Never>?
    private(set) var helpPanel: FuwaHelpPanel?
    private var helpTrackingArea: NSTrackingArea?

    init(title: String, text: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        imageScaling = .scaleNone
        imageFrameStyle = .none
        isEditable = false
        contentTintColor = .secondaryLabelColor
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        update(title: title, text: text)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { false }

    override func updateTrackingAreas() {
        if let helpTrackingArea { removeTrackingArea(helpTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        helpTrackingArea = area
        super.updateTrackingAreas()
        if visibleRect.isEmpty { dismissHelp() }
    }

    override func mouseEntered(with event: NSEvent) {
        dismissHelp()
        hoverTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.showHelp()
        }
    }

    override func mouseExited(with event: NSEvent) { dismissHelp() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        dismissHelp()
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidHide() {
        dismissHelp()
        super.viewDidHide()
    }

    private func showHelp() {
        guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor,
              !visibleRect.isEmpty, let screen = window.screen else { return }
        let icon = window.convertToScreen(convert(bounds, to: nil))
        let panel = FuwaHelpPanel(title: helpTitle, text: helpText,
            width: min(320, screen.visibleFrame.width - 16))
        panel.appearance = window.effectiveAppearance
        var origin = NSPoint(x: icon.midX - panel.frame.width / 2,
                             y: icon.minY - panel.frame.height - 6)
        let available = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        origin.x = min(max(origin.x, available.minX), available.maxX - panel.frame.width)
        if origin.y < available.minY { origin.y = icon.maxY + 6 }
        origin.y = min(max(origin.y, available.minY), available.maxY - panel.frame.height)
        panel.setFrameOrigin(origin)
        panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        helpPanel = panel
        window.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
    }

    private func dismissHelp() {
        hoverTask?.cancel()
        hoverTask = nil
        if let helpPanel {
            helpPanel.parent?.removeChildWindow(helpPanel)
            helpPanel.close()
        }
        helpPanel = nil
    }

    func update(title: String, text: String) {
        guard title != helpTitle || text != helpText else { return }
        helpTitle = title
        helpText = text
        // System tooltips have their own delay/activation rules. Keep one
        // explicit hover surface, including in nonactivating pin controls.
        toolTip = nil
        dismissHelp()
        setAccessibilityLabel(title)
        setAccessibilityHelp(text)
    }
}

@MainActor
final class FuwaHelpPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(title: String, text: String, width: CGFloat) {
        let heading = NSTextField(wrappingLabelWithString: title)
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        let body = NSTextField(wrappingLabelWithString: text)
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        let contentWidth = width - 24
        let titleHeight = ceil(heading.cell!.cellSize(forBounds:
            NSRect(x: 0, y: 0, width: contentWidth, height: 1000)).height)
        let bodyHeight = ceil(body.cell!.cellSize(forBounds:
            NSRect(x: 0, y: 0, width: contentWidth, height: 1000)).height)
        let height = titleHeight + bodyHeight + 30
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        let surface = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        surface.wantsLayer = true
        surface.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        surface.layer?.borderColor = NSColor.separatorColor.cgColor
        surface.layer?.borderWidth = 1
        surface.layer?.cornerRadius = 8
        heading.frame = NSRect(x: 12, y: height - 12 - titleHeight,
            width: contentWidth, height: titleHeight)
        body.frame = NSRect(x: 12, y: 12, width: contentWidth, height: bodyHeight)
        surface.addSubview(heading)
        surface.addSubview(body)
        contentView = surface
        setAccessibilityLabel(title)
    }
}
