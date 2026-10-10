import AppKit
import SwiftUI

/// A neutral information image with native hover help and no click action.
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

    func update(title: String, text: String) {
        toolTip = text
        setAccessibilityLabel(title)
        setAccessibilityHelp(text)
    }
}
