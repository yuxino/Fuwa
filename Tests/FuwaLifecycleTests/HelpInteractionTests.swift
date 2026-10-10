import AppKit
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct HelpInteractionTests {
    @Test func helpIsANeutralImageWithPassiveHoverAndNoClickAction() {
        _ = NSApplication.shared
        let view = FuwaHelpImageView(title: "Screen Recording", text: "Pictures stay on this Mac.")
        view.updateTrackingAreas()
        #expect(view.trackingAreas.contains {
            $0.options.contains([.activeAlways, .mouseEnteredAndExited, .inVisibleRect])
        })
        #expect(view.accessibilityRole() == .image)
        #expect(view.accessibilityLabel() == "Screen Recording")
        #expect(view.toolTip == nil)
        #expect(view.contentTintColor == .secondaryLabelColor)
        #expect(!view.isEditable)
        #expect(!view.acceptsFirstResponder)
        #expect(view.target == nil)
        #expect(view.action == nil)
        #expect(!view.accessibilityPerformPress())

        view.update(title: "Permissions", text: "Updated help")
        #expect(view.accessibilityLabel() == "Permissions")
        #expect(view.toolTip == nil)
        #expect(view.accessibilityHelp() == "Updated help")
        #expect(view.contentTintColor == .secondaryLabelColor)
    }
}

@Suite(.serialized)
@MainActor
struct HelpHoverPresentationTests {
    // Creates disposable windows without moving the mouse or posting input.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FUWA_HELP_HOVER_QA"] == "1"))
    func hoverShowsAndDismissesWithoutTakingFocus() async throws {
        let app = NSApplication.shared
        let controls = PinControlsPanel(contentRect: NSRect(x: 100, y: 100, width: 400, height: 200),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        controls.isReleasedWhenClosed = false
        let view = FuwaHelpImageView(title: "显示 / 隐藏快捷键",
            text: "按一次，隐藏所有置顶浮窗；再按一次，显示回来。原窗口不会关闭，已暂停的浮窗也不会重新更新。")
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        root.addSubview(view)
        view.setFrameOrigin(NSPoint(x: 120, y: 120))
        controls.contentView = root
        defer { view.removeFromSuperview(); controls.close() }
        controls.orderFrontRegardless()
        controls.makeKey()
        #expect(controls.isKeyWindow)
        let keyWindow = app.keyWindow
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let entered = try #require(NSEvent.enterExitEvent(with: .mouseEntered,
            location: .zero, modifierFlags: [], timestamp: 0, windowNumber: controls.windowNumber,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        view.mouseEntered(with: entered)
        try await Task.sleep(for: .milliseconds(350))
        let panel = try #require(view.helpPanel)
        #expect(panel.isVisible)
        #expect(panel.parent === controls)
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.canBecomeKey && !panel.canBecomeMain)
        #expect(controls.isVisible)
        #expect(app.keyWindow === keyWindow)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontPID)
        if let output = ProcessInfo.processInfo.environment["FUWA_HELP_HOVER_IMAGE"] {
            let surface = try #require(panel.contentView)
            let bitmap = try #require(surface.bitmapImageRepForCachingDisplay(in: surface.bounds))
            surface.cacheDisplay(in: surface.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: output))
        }
        view.update(title: "显示 / 隐藏快捷键",
            text: "按一次，隐藏所有置顶浮窗；再按一次，显示回来。原窗口不会关闭，已暂停的浮窗也不会重新更新。")
        #expect(view.helpPanel === panel)
        view.mouseExited(with: entered)
        #expect(view.helpPanel == nil)
        #expect(!panel.isVisible)
        view.mouseEntered(with: entered)
        view.mouseExited(with: entered)
        try await Task.sleep(for: .milliseconds(350))
        #expect(view.helpPanel == nil)
        view.mouseEntered(with: entered)
        view.removeFromSuperview()
        try await Task.sleep(for: .milliseconds(350))
        #expect(view.helpPanel == nil)
    }
}
