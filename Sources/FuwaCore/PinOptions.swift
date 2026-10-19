import Foundation

public enum PinPresentationMode: String, Codable, CaseIterable, Sendable {
    case followSource
    case reference
}

public enum PinSpaceScope: String, Codable, CaseIterable, Sendable {
    case allSpaces
    case currentSpace
}

public enum PinFrameRate: Int, Codable, CaseIterable, Sendable {
    case one = 1
    case five = 5
    case fifteen = 15
    case thirty = 30
    case sixty = 60
}

/// A region in the source window, normalized from its top-left corner.
public struct NormalizedCaptureRegion: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Per-pin choices. Defaults preserve the existing source-following workflow.
public struct PinOptions: Codable, Equatable, Sendable {
    public var presentationMode: PinPresentationMode = .followSource
    public var captureRegion: NormalizedCaptureRegion?
    public var spaceScope: PinSpaceScope = .allSpaces
    public var applicationScopeBundleIdentifier: String?
    public var frameRate: PinFrameRate = .thirty
    public var reducesFrameRateWhenIdle: Bool = true
    public var notifiesWhenIdle: Bool = false
    public var opacity: Double = 1 {
        didSet { opacity = Self.sanitizedOpacity(opacity) }
    }
    public var previewsOnHover: Bool = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case presentationMode, captureRegion, spaceScope, applicationScopeBundleIdentifier
        case frameRate, reducesFrameRateWhenIdle, notifiesWhenIdle, opacity, previewsOnHover
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        presentationMode = try values.decodeIfPresent(PinPresentationMode.self, forKey: .presentationMode) ?? .followSource
        captureRegion = try values.decodeIfPresent(NormalizedCaptureRegion.self, forKey: .captureRegion)
        spaceScope = try values.decodeIfPresent(PinSpaceScope.self, forKey: .spaceScope) ?? .allSpaces
        applicationScopeBundleIdentifier = try values.decodeIfPresent(String.self, forKey: .applicationScopeBundleIdentifier)
        frameRate = try values.decodeIfPresent(PinFrameRate.self, forKey: .frameRate) ?? .thirty
        reducesFrameRateWhenIdle = try values.decodeIfPresent(Bool.self, forKey: .reducesFrameRateWhenIdle) ?? true
        notifiesWhenIdle = try values.decodeIfPresent(Bool.self, forKey: .notifiesWhenIdle) ?? false
        opacity = Self.sanitizedOpacity(try values.decodeIfPresent(Double.self, forKey: .opacity) ?? 1)
        previewsOnHover = try values.decodeIfPresent(Bool.self, forKey: .previewsOnHover) ?? false
    }

    private static func sanitizedOpacity(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0.2, value)) : 1
    }
}
