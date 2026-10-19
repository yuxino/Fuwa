import CoreGraphics

public enum ReferencePreviewGeometry {
    /// Place the preview beside its reference, using the side with the most room.
    /// Equal-sized candidates prefer right, left, above, then below. The result
    /// never covers the reference; insufficient room to enlarge its picture returns .zero.
    public static func frame(reference: CGRect, aspect: CGSize, visibleFrame: CGRect) -> CGRect {
        // CGRect.infinite uses finite sentinel coordinates on CoreGraphics;
        // checking scalar finiteness alone would treat it as a real display.
        guard valid(visibleFrame), valid(reference) else { return .zero }
        let anchor = reference.intersection(visibleFrame)
        guard valid(anchor) else { return .zero }

        let maximumWidth = min(960, visibleFrame.width * 0.8)
        let maximumHeight = min(720, visibleFrame.height * 0.8)
        let source = valid(aspect) ? aspect : reference.size
        // Normalize first to avoid overflow for unusually large source sizes.
        let longestAxis = max(source.width, source.height)
        let unitWidth = source.width / longestAxis
        let unitHeight = source.height / longestAxis
        let preferredScale = max(480 / unitWidth, 320 / unitHeight,
                                 reference.width * 1.6 / unitWidth, reference.height * 1.6 / unitHeight)
        let gap: CGFloat = 12
        let spaces: [(side: Side, width: CGFloat, height: CGFloat)] = [
            (.right, visibleFrame.maxX - anchor.maxX - gap, visibleFrame.height),
            (.left, anchor.minX - visibleFrame.minX - gap, visibleFrame.height),
            (.above, visibleFrame.width, visibleFrame.maxY - anchor.maxY - gap),
            (.below, visibleFrame.width, anchor.minY - visibleFrame.minY - gap)
        ]
        var bestFrame = CGRect.zero
        var bestScale: CGFloat = 0
        for space in spaces {
            let availableWidth = min(maximumWidth, space.width)
            let availableHeight = min(maximumHeight, space.height)
            guard availableWidth >= min(96, maximumWidth), availableHeight >= min(64, maximumHeight) else { continue }
            let scale = min(preferredScale, availableWidth / unitWidth, availableHeight / unitHeight)
            guard scale > bestScale + 0.001 else { continue }
            // Extremely wide/tall content is aspect-fitted inside a usable
            // outer frame, rather than a sub-point window dimension.
            let width = max(min(96, maximumWidth), unitWidth * scale)
            let height = max(min(64, maximumHeight), unitHeight * scale)
            let x: CGFloat
            let y: CGFloat
            switch space.side {
            case .right, .left:
                x = space.side == .right ? anchor.maxX + gap : anchor.minX - gap - width
                y = min(max(anchor.midY - height / 2, visibleFrame.minY), visibleFrame.maxY - height)
            case .above, .below:
                x = min(max(anchor.midX - width / 2, visibleFrame.minX), visibleFrame.maxX - width)
                y = space.side == .above ? anchor.maxY + gap : anchor.minY - gap - height
            }
            bestFrame = CGRect(x: x, y: y, width: width, height: height)
            bestScale = scale
        }
        // Compare fitted picture scales, not outer frames: a letterboxed
        // reference can have a taller frame while showing a smaller picture.
        let referenceScale = min(reference.width / unitWidth, reference.height / unitHeight)
        return bestScale > referenceScale + 0.001 ? bestFrame : .zero
    }

    private enum Side { case right, left, above, below }

    private static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && valid(frame.size)
            && [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
    }

    private static func valid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}
