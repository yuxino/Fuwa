import AppKit
import Testing
@testable import Fuwa

@Suite(.serialized)
@MainActor
struct HelpInteractionTests {
    @Test func helpIsANeutralImageWithNativeTooltipAndNoClickAction() {
        _ = NSApplication.shared
        let view = FuwaHelpImageView(title: "Screen Recording", text: "Pictures stay on this Mac.")
        #expect(view.accessibilityRole() == .image)
        #expect(view.accessibilityLabel() == "Screen Recording")
        #expect(view.toolTip == "Pictures stay on this Mac.")
        #expect(view.contentTintColor == .secondaryLabelColor)
        #expect(!view.isEditable)
        #expect(!view.acceptsFirstResponder)
        #expect(view.target == nil)
        #expect(view.action == nil)
        #expect(!view.accessibilityPerformPress())

        view.update(title: "Permissions", text: "Updated help")
        #expect(view.accessibilityLabel() == "Permissions")
        #expect(view.toolTip == "Updated help")
        #expect(view.accessibilityHelp() == "Updated help")
        #expect(view.contentTintColor == .secondaryLabelColor)
    }
}
