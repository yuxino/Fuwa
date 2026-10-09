import AppKit
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct TerminationTests {
    @Test func quitShortcutReachesApplicationTermination() throws {
        let app = NSApplication.shared
        let previousDelegate = app.delegate
        let probe = QuitProbe()
        app.delegate = probe
        defer { app.delegate = previousDelegate }
        let menu = FuwaApplicationMenu.make(quitTitle: "Quit Fuwa")
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "q", charactersIgnoringModifiers: "q",
            isARepeat: false, keyCode: 12
        ))
        #expect(menu.performKeyEquivalent(with: event))
        #expect(probe.requestedTermination)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FUWA_HEADLESS_TESTS"] != "1",
                  "Visible window verification requires a dedicated desktop"))
    func terminationClosesUntrackedFloatingWindowsSynchronously() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.orderFrontRegardless()
        #expect(panel.isVisible)
        #expect(delegate.applicationShouldTerminate(app) == .terminateNow)
        #expect(!panel.isVisible)
        // AppKit follows the request callback with a will-terminate callback.
        // Cleanup must remain safe when both entry points run.
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(!panel.isVisible)
    }
}

@MainActor
private final class QuitProbe: NSObject, NSApplicationDelegate {
    var requestedTermination = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        requestedTermination = true
        return .terminateCancel
    }
}
