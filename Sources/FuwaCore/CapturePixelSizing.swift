import Foundation

public struct PixelDimensions: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var pixelCount: Int {
        let (count, overflowed) = width.multipliedReportingOverflow(by: height)
        return overflowed ? .max : count
    }
}

public enum CapturePixelSizing {
    public static func fittedDimensions(
        sourceWidth: Int,
        sourceHeight: Int,
        quality: CaptureQuality = .default
    ) -> PixelDimensions? {
        guard sourceWidth > 0, sourceHeight > 0,
              !sourceWidth.multipliedReportingOverflow(by: sourceHeight).overflow else { return nil }
        // Split integer division to avoid overflow and preserve exact native pixels.
        func scaled(_ axis: Int) -> Int {
            max(1, axis / 100 * quality.percentage + axis % 100 * quality.percentage / 100)
        }
        return PixelDimensions(width: scaled(sourceWidth), height: scaled(sourceHeight))
    }
}

/// Window geometry uses points; capture dimensions use the source display's pixels.
public enum LiveCaptureSizing {
    public static func fittedDimensions(
        pointWidth: Double,
        pointHeight: Double,
        pointScale: Double,
        quality: CaptureQuality = .default
    ) -> PixelDimensions? {
        guard pointWidth.isFinite, pointHeight.isFinite, pointScale.isFinite,
              pointWidth > 0, pointHeight > 0, pointScale > 0 else { return nil }
        let effectiveScale = max(1, pointScale)
        let width = ceil(pointWidth * effectiveScale)
        let height = ceil(pointHeight * effectiveScale)
        guard width.isFinite, height.isFinite,
              width < Double(Int.max), height < Double(Int.max),
              let dimensions = CapturePixelSizing.fittedDimensions(
                sourceWidth: max(2, Int(width)), sourceHeight: max(2, Int(height)), quality: quality
              ) else { return nil }
        return PixelDimensions(width: max(2, dimensions.width), height: max(2, dimensions.height))
    }
}
