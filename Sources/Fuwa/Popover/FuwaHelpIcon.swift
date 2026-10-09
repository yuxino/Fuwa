import SwiftUI

/// Keeps optional explanations nearby without filling the settings page.
struct FuwaHelpIcon: View {
    let title: String
    let text: String

    var body: some View {
        Image(systemName: "info.circle")
            .font(.caption)
            .foregroundStyle(FuwaAppearance.secondaryText)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .help(text)
            .accessibilityLabel(title)
            .accessibilityHint(text)
            .focusable()
            .focusEffectDisabled()
            .modifier(FuwaKeyboardFocus(cornerRadius: 3))
    }
}
