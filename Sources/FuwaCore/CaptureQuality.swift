/// Scale each captured axis relative to the source window's native pixels.
public struct CaptureQuality: RawRepresentable, Equatable, Hashable, Sendable {
    public static let minimumPercentage = 25
    public static let native = Self(percentage: 100)!
    public static let `default` = native

    public let percentage: Int

    public init?(percentage: Int) {
        guard (Self.minimumPercentage...100).contains(percentage) else { return nil }
        self.percentage = percentage
    }

    public init?(rawValue: String) {
        if rawValue == "native" { self = .native; return }
        guard rawValue.hasSuffix("%"), let percentage = Int(rawValue.dropLast()) else { return nil }
        self.init(percentage: percentage)
    }

    public var rawValue: String { "\(percentage)%" }
}
