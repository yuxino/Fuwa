import AppKit
import SwiftUI

/// A real help button provides native hover tips, keyboard focus and click-to-read help.
struct FuwaHelpIcon: View {
    let title: String
    let text: String

    var body: some View {
        FuwaHelpButtonRepresentable(title: title, text: text)
            .frame(width: 24, height: 24)
            // Explanations remain readable while the related capture action is busy.
            .environment(\.isEnabled, true)
    }
}

@MainActor
private struct FuwaHelpButtonRepresentable: NSViewRepresentable {
    let title: String
    let text: String
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> FuwaHelpButton {
        FuwaHelpButton(title: title, text: text)
    }

    func updateNSView(_ button: FuwaHelpButton, context: Context) {
        button.update(title: title, text: text, enabled: isEnabled)
    }

    static func dismantleNSView(_ button: FuwaHelpButton, coordinator: ()) {
        button.closeHelp()
    }
}

@MainActor
final class FuwaHelpButton: NSButton, NSPopoverDelegate {
    private var helpTitle = ""
    private var helpText = ""
    private var hoverTrackingArea: NSTrackingArea?
    private(set) var isHovered = false
    private(set) var helpPopover: NSPopover?

    init(title: String, text: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        self.title = ""
        image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        imagePosition = .imageOnly
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .default
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        target = self
        action = #selector(toggleHelp)
        update(title: title, text: text, enabled: true)
    }

    required init?(coder: NSCoder) { nil }

    func update(title: String, text: String, enabled: Bool) {
        let copyChanged = helpTitle != title || helpText != text
        helpTitle = title
        helpText = text
        toolTip = text
        setAccessibilityLabel(title)
        setAccessibilityHelp(text)
        isEnabled = enabled
        contentTintColor = enabled ? .secondaryLabelColor : .disabledControlTextColor
        if !enabled { isHovered = false; closeHelp() }
        if copyChanged, let helpPopover {
            helpPopover.contentViewController = helpContent()
        }
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = isEnabled
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered && isEnabled {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        super.draw(dirtyRect)
    }

    override func resetCursorRects() {
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { isHovered = false; closeHelp() }
    }

    override func cancelOperation(_ sender: Any?) {
        if helpPopover?.isShown == true { closeHelp() } else { super.cancelOperation(sender) }
    }

    @objc private func toggleHelp() {
        guard isEnabled, window?.isVisible == true else { return }
        if helpPopover?.isShown == true { closeHelp(); return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = helpContent()
        popover.delegate = self
        helpPopover = popover
        window?.makeFirstResponder(self)
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }

    func popoverDidClose(_ notification: Notification) {
        // AppKit restores the parent key window after closing its transient child.
        // Defer the check so outside clicks still dismiss floating controls.
        if let panel = window as? PinControlsPanel {
            Task { @MainActor [weak panel] in panel?.finishHelpInteraction() }
        }
    }

    static func openHelp(in view: NSView?) -> FuwaHelpButton? {
        guard let view else { return nil }
        if let button = view as? FuwaHelpButton, button.helpPopover?.isShown == true { return button }
        return view.subviews.lazy.compactMap { openHelp(in: $0) }.first
    }

    func closeHelp() {
        helpPopover?.close()
        helpPopover = nil
    }

    private func helpContent() -> NSViewController {
        NSHostingController(rootView: FuwaHelpExplanation(title: helpTitle, text: helpText))
    }
}

struct FuwaHelpExplanation: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.callout.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(text).font(.callout).foregroundStyle(FuwaAppearance.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 220, alignment: .leading)
        .fuwaLightSurface()
        .accessibilityElement(children: .contain)
    }
}
