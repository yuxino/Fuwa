import CoreGraphics
import FuwaCore
import Testing

struct ReferencePreviewGeometryTests {
    @Test func previewEnlargesReferenceWithoutChangingItsAspect() {
        let display = CGRect(x: 0, y: 40, width: 1600, height: 1000)
        let reference = CGRect(x: 30, y: 100, width: 400, height: 300)
        let frame = ReferencePreviewGeometry.frame(reference: reference, aspect: reference.size, visibleFrame: display)
        #expect(frame.size == CGSize(width: 640, height: 480))
        #expect(frame.midX == display.midX)
        #expect(frame.midY == display.midY)
        #expect(frame == ReferencePreviewGeometry.frame(reference: reference.offsetBy(dx: 500, dy: 300),
                                                        aspect: reference.size, visibleFrame: display))
    }

    @Test func largeReferenceFitsTheDisplayAndPreviewLimit() {
        for display in [CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                        CGRect(x: 100, y: 982, width: 800, height: 600),
                        CGRect(x: 1512, y: -500, width: 1440, height: 900)] {
            let reference = CGRect(x: display.minX, y: display.minY, width: 1600, height: 900)
            let frame = ReferencePreviewGeometry.frame(reference: reference, aspect: reference.size, visibleFrame: display)
            #expect(display.contains(frame))
            #expect(frame.width <= min(960, display.width * 0.8))
            #expect(frame.height <= min(720, display.height * 0.8))
            #expect(abs(frame.width / frame.height - 16 / 9.0) < 0.00001)
            #expect(frame.midX == display.midX)
            #expect(frame.midY == display.midY)
        }
    }

    @Test func thinContentRetainsAUsableOuterFrame() {
        let display = CGRect(x: -1600, y: -900, width: 1600, height: 900)
        for aspect in [CGSize(width: 1_000_000, height: 1), CGSize(width: 1, height: 1_000_000),
                       CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.leastNonzeroMagnitude),
                       CGSize(width: CGFloat.leastNonzeroMagnitude, height: CGFloat.greatestFiniteMagnitude)] {
            let frame = ReferencePreviewGeometry.frame(reference: .zero, aspect: aspect, visibleFrame: display)
            #expect(display.contains(frame))
            #expect(frame.width >= 96)
            #expect(frame.height >= 64)
            #expect(frame.width <= 960)
            #expect(frame.height <= 720)
        }
    }

    @Test func tinyDisplayStillContainsPreview() {
        let display = CGRect(x: -25, y: -10, width: 50, height: 20)
        let frame = ReferencePreviewGeometry.frame(reference: .zero, aspect: CGSize(width: 16, height: 9),
                                                   visibleFrame: display)
        #expect(display.contains(frame))
        #expect(frame.width <= display.width * 0.8)
        #expect(frame.height <= display.height * 0.8)
    }

    @Test func invalidAspectUsesReferenceThenDefaultAndInvalidDisplayIsRejected() {
        let display = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let reference = CGRect(x: 40, y: 50, width: 400, height: 300)
        for aspect in [CGSize.zero, CGSize(width: -1, height: 3), CGSize(width: CGFloat.infinity, height: 3)] {
            let frame = ReferencePreviewGeometry.frame(reference: reference, aspect: aspect, visibleFrame: display)
            #expect(frame.size == CGSize(width: 640, height: 480))
            let fallback = ReferencePreviewGeometry.frame(reference: .zero, aspect: aspect, visibleFrame: display)
            #expect(fallback.size == CGSize(width: 480, height: 360))
        }
        for invalidDisplay in [CGRect.zero, CGRect.null, CGRect.infinite,
                               CGRect(x: 0, y: 0, width: -1600, height: 1000),
                               CGRect(x: 0, y: 0, width: 1600, height: -1000)] {
            #expect(ReferencePreviewGeometry.frame(reference: reference, aspect: reference.size,
                                                    visibleFrame: invalidDisplay) == .zero)
        }
    }
}
