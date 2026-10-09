public enum CaptureQuality: String, CaseIterable, Sendable {
    case fourMegapixels = "4mp"
    case nineMegapixels = "9mp"
    case sixteenMegapixels = "16mp"
    case native

    public static let `default`: Self = .fourMegapixels

    public var maximumPixelCount: Int? {
        switch self {
        case .fourMegapixels: 4_000_000
        case .nineMegapixels: 9_000_000
        case .sixteenMegapixels: 16_000_000
        case .native: nil
        }
    }
}
