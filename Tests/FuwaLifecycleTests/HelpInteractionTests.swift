import AppKit
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct HelpInteractionTests {
    @Test func helpIsANativeButtonWithTooltipAndDisabledHoverFeedback() throws {
        _ = NSApplication.shared
        let button = FuwaHelpButton(title: "Screen Recording", text: "Pictures stay on this Mac.")
        #expect(button.accessibilityRole() == .button)
        #expect(button.accessibilityLabel() == "Screen Recording")
        #expect(button.toolTip == "Pictures stay on this Mac.")
        button.updateTrackingAreas()
        #expect(button.trackingAreas.contains { $0.options.contains(.activeAlways) && $0.options.contains(.inVisibleRect) })
        let event = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
            trackingNumber: 0, userData: nil))
        button.mouseEntered(with: event)
        #expect(button.isHovered)
        button.mouseExited(with: event)
        #expect(!button.isHovered)
        button.update(title: "Permissions", text: "Updated help", enabled: false)
        button.mouseEntered(with: event)
        #expect(!button.isHovered)
        #expect(button.toolTip == "Updated help")
        #expect(button.accessibilityHelp() == "Updated help")
    }

}
