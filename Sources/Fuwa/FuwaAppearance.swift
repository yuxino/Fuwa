import SwiftUI

/// Opaque surfaces keep Fuwa white, including when macOS uses Dark Mode.
enum FuwaAppearance {
    static let canvas = Color.white
    static let sidebar = Color(white: 0.975)
    static let border = Color(white: 0.85)
    static let ink = Color(white: 0.12)
    static let secondaryText = Color(white: 0.40)
    static let success = Color(red: 0.15, green: 0.42, blue: 0.24)
    static let warning = Color(red: 0.64, green: 0.37, blue: 0.10)
    static let error = Color(red: 0.73, green: 0.19, blue: 0.17)
}

enum FuwaTypography {
    static let settingTitle = Font.body.weight(.medium)
    static let explanation = Font.caption
    static let sectionTitle = Font.caption.weight(.semibold)
}

extension View {
    func fuwaLightSurface() -> some View {
        background(FuwaAppearance.canvas)
            .tint(FuwaAppearance.ink)
            .preferredColorScheme(.light)
            .environment(\.colorScheme, .light)
    }
}
