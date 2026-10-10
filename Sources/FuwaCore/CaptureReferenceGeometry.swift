import CoreGraphics

/// Capture coordinates are points measured from the source's top-left corner.
public enum CaptureReferenceGeometry {
    public static func sanitized(_ region: NormalizedCaptureRegion?) -> NormalizedCaptureRegion? {
        guard let region,
              [region.x, region.y, region.width, region.height].allSatisfy(\.isFinite),
              region.width > 0, region.height > 0 else { return nil }
        let left = max(0, min(1, region.x))
        let top = max(0, min(1, region.y))
        let right = max(left, min(1, region.x + region.width))
        let bottom = max(top, min(1, region.y + region.height))
        guard right - left > 0.001, bottom - top > 0.001 else { return nil }
        return NormalizedCaptureRegion(x: left, y: top, width: right - left, height: bottom - top)
    }

    public static func sourceRect(pointSize: CGSize, region: NormalizedCaptureRegion?) -> CGRect {
        let region = sanitized(region) ?? NormalizedCaptureRegion(x: 0, y: 0, width: 1, height: 1)
        return CGRect(x: Double(pointSize.width) * region.x, y: Double(pointSize.height) * region.y,
                      width: Double(pointSize.width) * region.width, height: Double(pointSize.height) * region.height)
    }

    /// Normalized-region arithmetic can produce 480.00000000000006 pixels.
    /// Snap only machine-rounding noise before native sizing rounds up; genuine
    /// fractional pixels still round up and retain the complete selected area.
    public static func pixelStablePointSize(_ size: CGSize, pointScale: CGFloat) -> CGSize {
        let scale = max(1, pointScale)
        func stable(_ axis: CGFloat) -> CGFloat {
            let pixels = axis * scale
            let nearest = pixels.rounded()
            if abs(pixels - nearest) <= max(1, abs(pixels)) * 1e-12 { return nearest / scale }
            return axis
        }
        return CGSize(width: stable(size.width), height: stable(size.height))
    }

    /// Map a selection in an aspect-fitted AppKit image back to the complete source.
    public static func selectedRegion(selection: CGRect, imageRect: CGRect,
                                      within previous: NormalizedCaptureRegion?) -> NormalizedCaptureRegion? {
        guard imageRect.width > 0, imageRect.height > 0 else { return nil }
        let clipped = selection.standardized.intersection(imageRect)
        guard !clipped.isNull,
              clipped.width >= min(3, imageRect.width),
              clipped.height >= min(3, imageRect.height) else { return nil }
        let base = sanitized(previous) ?? NormalizedCaptureRegion(x: 0, y: 0, width: 1, height: 1)
        return sanitized(NormalizedCaptureRegion(
            x: base.x + Double((clipped.minX - imageRect.minX) / imageRect.width) * base.width,
            y: base.y + Double((imageRect.maxY - clipped.maxY) / imageRect.height) * base.height,
            width: Double(clipped.width / imageRect.width) * base.width,
            height: Double(clipped.height / imageRect.height) * base.height
        ))
    }

    public static func aspectFit(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    public static func resizedFrame(_ frame: CGRect, requestedWidth: CGFloat, aspect: CGSize,
                                    maximumSize: CGSize? = nil) -> CGRect {
        guard aspect.width.isFinite, aspect.height.isFinite,
              aspect.width > 0, aspect.height > 0, requestedWidth.isFinite else { return frame }
        // Keep the top-left corner stable while resizing the bottom-right handle.
        let ratio = aspect.height / aspect.width
        var width = max(max(96, 64 / ratio), requestedWidth)
        var minimumWidth: CGFloat = 0
        var minimumHeight: CGFloat = 0
        if let maximumSize, maximumSize.width.isFinite, maximumSize.height.isFinite,
           maximumSize.width > 0, maximumSize.height > 0 {
            minimumWidth = min(96, maximumSize.width)
            minimumHeight = min(64, maximumSize.height)
            let proportionalMinimum = max(minimumWidth, minimumHeight / ratio)
            if minimumWidth * ratio > maximumSize.height {
                // A tall picture needs a wider outer frame than its pixels.
                // Resize that frame using its current proportions, so a smaller
                // request can reduce height even after width reaches its minimum.
                // Reconciliation with the current width preserves that height.
                let outerRatio = frame.width.isFinite && frame.height.isFinite
                    && frame.width > 0 && frame.height > 0 ? frame.height / frame.width : ratio
                let height = max(minimumHeight, min(maximumSize.height, max(0, requestedWidth) * outerRatio))
                return CGRect(x: frame.minX, y: frame.maxY - height, width: minimumWidth, height: height)
            }
            if proportionalMinimum > maximumSize.width || proportionalMinimum * ratio > maximumSize.height {
                // A very wide picture cannot meet both interaction minimums
                // proportionally. Give its aspect-fitted pixels a
                // usable outer frame rather than a sub-point mouse target.
                width = max(minimumWidth, requestedWidth)
            }
            width = min(width, maximumSize.width, maximumSize.height / ratio)
        }
        let height = max(minimumHeight, width * ratio)
        width = max(minimumWidth, width)
        return CGRect(x: frame.minX, y: frame.maxY - height, width: width, height: height)
    }
}
