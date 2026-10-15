import AppKit
import FuwaCore
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct CaptureAvailabilityTests {
    @Test func menuDisablesPauseUntilTheReplacementFrameArrives() throws {
        _ = NSApplication.shared
        let model = AppModel(copy: FuwaCopy(language: .english))
        let controller = StatusBarController(model: model, statusItem: nil)
        defer { controller.invalidate() }
        var pin = PinSnapshot(id: UUID(), sourceWindowID: 100, applicationName: "Preview",
                              bundleIdentifier: nil, windowTitle: "Reference",
                              state: .live, errorMessage: nil, isAwaitingFreshFrame: true)
        model.updatePins([pin])
        let waitingMenu = try #require(controller.makeMenu().items.first { $0.submenu != nil }?.submenu)
        let waitingPause = try #require(waitingMenu.items.first { $0.title == model.copy.text(.freeze) })
        #expect(!waitingPause.isEnabled)
        #expect(waitingMenu.items.contains { $0.title == model.copy.text(.unpin) && $0.isEnabled })

        pin.isAwaitingFreshFrame = false
        model.updatePins([pin])
        let liveMenu = try #require(controller.makeMenu().items.first { $0.submenu != nil }?.submenu)
        #expect(liveMenu.items.contains { $0.title == model.copy.text(.freeze) && $0.isEnabled })

        // Hidden live pins already retain a complete frame. Pausing that frame
        // remains possible without restoring capture or revealing the picture.
        pin.isHidden = true
        model.updatePins([pin])
        let hiddenMenu = try #require(controller.makeMenu().items.first { $0.submenu != nil }?.submenu)
        #expect(hiddenMenu.items.contains { $0.title == model.copy.text(.freeze) && $0.isEnabled })
    }
}
