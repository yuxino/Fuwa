import CoreGraphics

/// All inputs use AppKit coordinates, including screens left of or above primary.
public enum FloatingControlsLayout {
    public static func frame(source: CGRect, visible: CGRect, size: CGSize = CGSize(width: 380, height: 164)) -> CGRect {
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let proposedY = source.maxY + height <= visible.maxY ? source.maxY : source.minY - height
        return CGRect(
            x: max(visible.minX, min(source.maxX - width, visible.maxX - width)),
            y: max(visible.minY, min(proposedY, visible.maxY - height)),
            width: width, height: height
        )
    }

    public static func screenIndex(source: CGRect, screens: [CGRect]) -> Int? {
        screens.indices.max { a, b in
            let left = source.intersection(screens[a])
            let right = source.intersection(screens[b])
            let leftArea = left.isNull ? 0 : left.width * left.height
            let rightArea = right.isNull ? 0 : right.width * right.height
            if leftArea != rightArea { return leftArea < rightArea }
            // No overlap (e.g. a disconnected display): choose the nearest screen.
            let leftDistance = distanceSquared(source, screens[a])
            let rightDistance = distanceSquared(source, screens[b])
            return leftDistance > rightDistance
        }
    }

    /// Recover a frozen view only when it has no visible pixels on any screen.
    /// Keep the image's aspect ratio when the remaining display is smaller.
    public static func recoveredFrame(source: CGRect, visibleScreens: [CGRect]) -> CGRect {
        guard source.width > 0, source.height > 0,
              !visibleScreens.contains(where: {
                  let overlap = source.intersection($0)
                  return !overlap.isNull && overlap.width > 0 && overlap.height > 0
              }),
              let index = screenIndex(source: source, screens: visibleScreens) else { return source }
        let visible = visibleScreens[index]
        guard visible.width > 0, visible.height > 0 else { return source }
        let scale = min(1, min(visible.width / source.width, visible.height / source.height))
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(
            x: max(visible.minX, min(source.minX, visible.maxX - size.width)),
            y: max(visible.minY, min(source.minY, visible.maxY - size.height)),
            width: size.width, height: size.height
        )
    }

    private static func distanceSquared(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let x = a.midX - b.midX
        let y = a.midY - b.midY
        return x * x + y * y
    }
}
