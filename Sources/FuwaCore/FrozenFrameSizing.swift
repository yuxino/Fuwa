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

public enum FrozenFrameSizing {
    public static func fittedDimensions(
        sourceWidth: Int,
        sourceHeight: Int,
        maxPixels: Int? = CaptureQuality.default.maximumPixelCount
    ) -> PixelDimensions? {
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }
        guard let maxPixels else {
            guard !sourceWidth.multipliedReportingOverflow(by: sourceHeight).overflow else {
                return nil
            }
            return PixelDimensions(width: sourceWidth, height: sourceHeight)
        }
        guard maxPixels > 0 else { return nil }

        let sourcePixels = Double(sourceWidth) * Double(sourceHeight)
        guard sourcePixels > Double(maxPixels) else {
            return PixelDimensions(width: sourceWidth, height: sourceHeight)
        }

        let scale = sqrt(Double(maxPixels) / sourcePixels)
        let scaledWidth = min(maxPixels, max(1, Int(floor(Double(sourceWidth) * scale))))
        let scaledHeight = max(1, Int(floor(Double(sourceHeight) * scale)))

        // Independently flooring both axes normally stays within the budget. The
        // division guard also covers extreme aspect ratios and floating-point
        // rounding at the boundary.
        let budgetedHeight = min(scaledHeight, max(1, maxPixels / scaledWidth))
        return PixelDimensions(width: scaledWidth, height: budgetedHeight)
    }
}

/// Bounds live ScreenCaptureKit surfaces before they reach the per-stream
/// frame queue. Window geometry is reported in points, while stream dimensions
/// are configured in pixels.
public enum LiveCaptureSizing {
    public static let maximumPixelCount = 4_000_000

    public static func fittedDimensions(
        pointWidth: Double,
        pointHeight: Double,
        pointScale: Double,
        maxPixels: Int? = CaptureQuality.default.maximumPixelCount
    ) -> PixelDimensions? {
        guard pointWidth.isFinite,
              pointHeight.isFinite,
              pointScale.isFinite,
              pointWidth > 0,
              pointHeight > 0,
              maxPixels.map({ $0 >= 4 }) ?? true else {
            return nil
        }

        let effectiveScale = max(1, pointScale)
        let requestedWidth = ceil(pointWidth * effectiveScale)
        let requestedHeight = ceil(pointHeight * effectiveScale)
        guard requestedWidth.isFinite,
              requestedHeight.isFinite,
              requestedWidth > 0,
              requestedHeight > 0,
              requestedWidth < Double(Int.max),
              requestedHeight < Double(Int.max) else {
            return nil
        }

        guard let fitted = FrozenFrameSizing.fittedDimensions(
            sourceWidth: max(2, Int(requestedWidth)),
            sourceHeight: max(2, Int(requestedHeight)),
            maxPixels: maxPixels
        ) else {
            return nil
        }

        guard let maxPixels else { return fitted }

        // ScreenCaptureKit requires useful non-zero surfaces. Keep both axes at
        // least two pixels without letting an extreme aspect ratio escape the
        // total pixel budget after that adjustment.
        let maximumLongDimension = maxPixels / 2
        let width = min(maximumLongDimension, max(2, fitted.width))
        let height = min(maxPixels / width, max(2, fitted.height))
        return PixelDimensions(width: width, height: height)
    }
}
