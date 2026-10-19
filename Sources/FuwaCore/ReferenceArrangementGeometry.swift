import CoreGraphics

public enum ReferenceArrangementCorner: String, CaseIterable, Codable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    private var isRight: Bool { self == .topRight || self == .bottomRight }
    private var isTop: Bool { self == .topLeft || self == .topRight }

    fileprivate var horizontalDirection: CGFloat { isRight ? -1 : 1 }
    fileprivate var verticalDirection: CGFloat { isTop ? -1 : 1 }
}

/// Arranges references in stable order, using AppKit's bottom-left coordinates.
/// Existing sizes are retained when possible. Oversized references first fit the
/// display, then all references shrink together only if more space is needed.
public enum ReferenceArrangementGeometry {
    public static func frames(_ references: [CGRect], in visibleFrame: CGRect,
                              corner: ReferenceArrangementCorner = .topRight) -> [CGRect] {
        guard !references.isEmpty else { return [] }
        guard !visibleFrame.isNull, !visibleFrame.isInfinite, valid(visibleFrame.size),
              [visibleFrame.minX, visibleFrame.minY, visibleFrame.maxX, visibleFrame.maxY]
                .allSatisfy(\.isFinite) else {
            return Array(repeating: .zero, count: references.count)
        }

        let shorterAxis = min(visibleFrame.width, visibleFrame.height)
        let margin = min(16, shorterAxis / 10)
        let gap = min(12, shorterAxis / max(4, CGFloat(references.count) * 2))
        let available = visibleFrame.insetBy(dx: margin, dy: margin)
        let sizes = references.map { fitted(valid($0.size) ? $0.size : CGSize(width: 320, height: 180),
                                             within: available.size) }

        var scale: CGFloat = 1
        var columns = layout(sizes, scale: scale, available: available.size, gap: gap)
        if columns == nil {
            // For a fixed scale, the layout finds the narrowest valid set of
            // columns. Feasibility therefore changes monotonically with scale.
            var lower: CGFloat = 0
            var upper: CGFloat = 1
            for _ in 0..<48 {
                let candidate = (lower + upper) / 2
                if layout(sizes, scale: candidate, available: available.size, gap: gap) != nil {
                    lower = candidate
                } else {
                    upper = candidate
                }
            }
            scale = lower
            columns = layout(sizes, scale: scale, available: available.size, gap: gap)
        }

        guard let columns else { return Array(repeating: .zero, count: references.count) }
        var result: [CGRect] = []
        let horizontal = corner.horizontalDirection
        let vertical = corner.verticalDirection
        var columnEdge = horizontal > 0 ? available.minX : available.maxX
        for column in columns {
            var rowEdge = vertical > 0 ? available.minY : available.maxY
            var columnWidth: CGFloat = 0
            for index in column {
                let size = CGSize(width: sizes[index].width * scale, height: sizes[index].height * scale)
                let x = horizontal > 0 ? columnEdge : columnEdge - size.width
                let y = vertical > 0 ? rowEdge : rowEdge - size.height
                // Clamp arithmetic noise at screen edges without rounding away
                // each reference's proportions.
                result.append(CGRect(x: min(max(x, available.minX), available.maxX - size.width),
                                     y: min(max(y, available.minY), available.maxY - size.height),
                                     width: size.width, height: size.height))
                rowEdge += vertical * (size.height + gap)
                columnWidth = max(columnWidth, size.width)
            }
            columnEdge += horizontal * (columnWidth + gap)
        }
        return result
    }

    /// Each column contains a contiguous slice, preserving the caller's order.
    /// Dynamic programming avoids a greedy packing choice unnecessarily shrinking
    /// windows with mixed portrait and landscape proportions.
    private static func layout(_ sizes: [CGSize], scale: CGFloat, available: CGSize,
                               gap: CGFloat) -> [Range<Int>]? {
        var widths = Array(repeating: CGFloat.infinity, count: sizes.count + 1)
        var previous = Array(repeating: 0, count: sizes.count + 1)
        var counts = Array(repeating: Int.max, count: sizes.count + 1)
        widths[0] = 0
        counts[0] = 0
        for end in 1...sizes.count {
            var height: CGFloat = 0
            var width: CGFloat = 0
            for start in stride(from: end - 1, through: 0, by: -1) {
                height += sizes[start].height * scale + (start == end - 1 ? 0 : gap)
                guard height <= available.height else { break }
                width = max(width, sizes[start].width * scale)
                guard widths[start].isFinite else { continue }
                let candidate = widths[start] + width + (start == 0 ? 0 : gap)
                let columnCount = counts[start] + 1
                if candidate < widths[end] || (candidate == widths[end] && columnCount < counts[end]) {
                    widths[end] = candidate
                    previous[end] = start
                    counts[end] = columnCount
                }
            }
        }
        guard widths[sizes.count] <= available.width else { return nil }
        var columns: [Range<Int>] = []
        var end = sizes.count
        while end > 0 {
            let start = previous[end]
            columns.append(start..<end)
            end = start
        }
        return columns.reversed()
    }

    private static func fitted(_ size: CGSize, within available: CGSize) -> CGSize {
        guard size.width > available.width || size.height > available.height else { return size }
        let longestAxis = max(size.width, size.height)
        let unitWidth = size.width / longestAxis
        let unitHeight = size.height / longestAxis
        let extent = min(longestAxis, available.width / unitWidth, available.height / unitHeight)
        return CGSize(width: unitWidth * extent, height: unitHeight * extent)
    }

    private static func valid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}
