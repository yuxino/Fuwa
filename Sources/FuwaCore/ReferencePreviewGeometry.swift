import CoreGraphics

public enum ReferencePreviewGeometry {
    /// Keep the preview stable while the pointer moves within its reference.
    /// The caller supplies the reference's display, so negative display origins
    /// and displays above or below the main screen need no special treatment.
    public static func frame(reference: CGRect, aspect: CGSize, visibleFrame: CGRect) -> CGRect {
        // CGRect.infinite uses finite sentinel coordinates on CoreGraphics;
        // checking scalar finiteness alone would treat it as a real display.
        guard !visibleFrame.isNull, !visibleFrame.isInfinite, valid(visibleFrame.size),
              [visibleFrame.minX, visibleFrame.minY, visibleFrame.maxX, visibleFrame.maxY]
                .allSatisfy(\.isFinite) else { return .zero }

        let maximumWidth = min(960, visibleFrame.width * 0.8)
        let maximumHeight = min(720, visibleFrame.height * 0.8)
        let source = valid(aspect) ? aspect : valid(reference.size) ? reference.size : CGSize(width: 4, height: 3)
        // Normalize first to avoid overflow for unusually large source sizes.
        let longestAxis = max(source.width, source.height)
        let unitWidth = source.width / longestAxis
        let unitHeight = source.height / longestAxis
        let maximumScale = min(maximumWidth / unitWidth, maximumHeight / unitHeight)
        let referenceWidth = reference.width.isFinite ? max(0, reference.width) : 0
        let referenceHeight = reference.height.isFinite ? max(0, reference.height) : 0
        let preferredScale = max(480 / unitWidth, 320 / unitHeight,
                                 referenceWidth * 1.6 / unitWidth, referenceHeight * 1.6 / unitHeight)
        let scale = min(maximumScale, preferredScale)
        // Extremely wide/tall content is aspect-fitted inside a usable outer
        // frame, rather than giving the preview a sub-point window dimension.
        let width = max(min(96, maximumWidth), unitWidth * scale)
        let height = max(min(64, maximumHeight), unitHeight * scale)
        return CGRect(x: visibleFrame.midX - width / 2, y: visibleFrame.midY - height / 2,
                      width: width, height: height)
    }

    private static func valid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}
