import CoreGraphics
import FuwaCore
import Testing

struct ReferencePreviewGeometryTests {
    @Test func previewEnlargesBesideReferenceAndKeepsItsAspect() {
        let display = CGRect(x: 0, y: 40, width: 1600, height: 1000)
        let reference = CGRect(x: 30, y: 100, width: 400, height: 300)
        let frame = ReferencePreviewGeometry.frame(reference: reference, aspect: reference.size, visibleFrame: display)
        #expect(frame.size == CGSize(width: 640, height: 480))
        #expect(frame.minX == reference.maxX + 12)
        #expect(frame.minY == display.minY)
        #expect(!frame.intersects(reference))
        #expect(frame == ReferencePreviewGeometry.frame(reference: reference, aspect: reference.size, visibleFrame: display))
    }

    @Test func choosesAllFourSidesAccordingToAvailableRoom() {
        let display = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let right = CGRect(x: 20, y: 350, width: 400, height: 300)
        let left = CGRect(x: 1180, y: 350, width: 400, height: 300)
        let above = CGRect(x: 500, y: 20, width: 600, height: 200)
        let below = CGRect(x: 500, y: 780, width: 600, height: 200)
        let references = [right, left, above, below]
        let frames = references.map { ReferencePreviewGeometry.frame(reference: $0, aspect: $0.size, visibleFrame: display) }
        #expect(frames[0].minX == right.maxX + 12)
        #expect(frames[1].maxX == left.minX - 12)
        #expect(frames[2].minY == above.maxY + 12)
        #expect(frames[3].maxY == below.minY - 12)
        for (reference, frame) in zip(references, frames) {
            #expect(display.contains(frame))
            #expect(!frame.intersects(reference))
        }
    }

    @Test func fitsDisplayOffsetsAndPreviewLimitWithoutCoveringReference() {
        for display in [CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                        CGRect(x: 100, y: 982, width: 800, height: 600),
                        CGRect(x: 1512, y: -500, width: 1440, height: 900)] {
            for y in [display.minY, display.midY - 90, display.maxY - 180] {
                let reference = CGRect(x: display.minX + 20, y: y, width: 320, height: 180)
                let frame = ReferencePreviewGeometry.frame(reference: reference, aspect: reference.size, visibleFrame: display)
                #expect(display.contains(frame))
                #expect(!frame.intersects(reference))
                #expect(frame.width <= min(960, display.width * 0.8))
                #expect(frame.height <= min(720, display.height * 0.8))
                #expect(frame.width > reference.width && frame.height > reference.height)
                #expect(abs(frame.width / frame.height - 16 / 9.0) < 0.00001)
            }
        }
    }

    @Test func reducesPreviewWhenThePreferredSizeDoesNotFitBesideReference() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let reference = CGRect(x: 400, y: 250, width: 200, height: 200)
        let frame = ReferencePreviewGeometry.frame(reference: reference, aspect: reference.size, visibleFrame: display)
        #expect(frame.size == CGSize(width: 388, height: 388))
        #expect(frame.minX == reference.maxX + 12)
        #expect(display.contains(frame))
        #expect(!frame.intersects(reference))
    }

    @Test func availableSideSpaceMustActuallyEnlargeThePicture() {
        let examples = [
            (CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 400, y: 250, width: 640, height: 400)),
            (CGRect(x: 0, y: 0, width: 1224, height: 924), CGRect(x: 412, y: 312, width: 400, height: 300))
        ]
        for (display, reference) in examples {
            #expect(ReferencePreviewGeometry.frame(reference: reference, aspect: reference.size, visibleFrame: display) == .zero)
        }
    }

    @Test func comparesThePictureInsideALetterboxedReference() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let reference = CGRect(x: 560, y: 130, width: 320, height: 640)
        let aspect = CGSize(width: 1920, height: 1080)
        let frame = ReferencePreviewGeometry.frame(reference: reference, aspect: aspect, visibleFrame: display)
        let originalPicture = CaptureReferenceGeometry.aspectFit(imageSize: aspect, in: reference)
        let previewPicture = CaptureReferenceGeometry.aspectFit(imageSize: aspect, in: frame)
        #expect(previewPicture.width > originalPicture.width)
        #expect(previewPicture.height > originalPicture.height)
        #expect(frame.height < reference.height)
        #expect(!frame.intersects(reference))
    }

    @Test func partiallyOffscreenReferenceUsesItsVisibleEdge() {
        let display = CGRect(x: -1600, y: -900, width: 1600, height: 900)
        let reference = CGRect(x: -1700, y: -850, width: 400, height: 300)
        let frame = ReferencePreviewGeometry.frame(reference: reference, aspect: reference.size, visibleFrame: display)
        #expect(frame.minX == reference.maxX + 12)
        #expect(display.contains(frame))
        #expect(!frame.intersects(reference))
    }

    @Test func thinContentRetainsAUsableOuterFrame() {
        let display = CGRect(x: -1600, y: -900, width: 1600, height: 900)
        let reference = CGRect(x: -1500, y: -800, width: 200, height: 100)
        for aspect in [CGSize(width: 1_000_000, height: 1), CGSize(width: 1, height: 1_000_000),
                       CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.leastNonzeroMagnitude),
                       CGSize(width: CGFloat.leastNonzeroMagnitude, height: CGFloat.greatestFiniteMagnitude)] {
            let frame = ReferencePreviewGeometry.frame(reference: reference, aspect: aspect, visibleFrame: display)
            #expect(display.contains(frame))
            #expect(!frame.intersects(reference))
            #expect(frame.width >= 96)
            #expect(frame.height >= 64)
            #expect(frame.width <= 960)
            #expect(frame.height <= 720)
        }
    }

    @Test func noUsefulSpaceDoesNotCoverReference() {
        let display = CGRect(x: -800, y: 100, width: 800, height: 600)
        for reference in [display, display.insetBy(dx: 30, dy: 30), display.offsetBy(dx: 1000, dy: 0)] {
            #expect(ReferencePreviewGeometry.frame(reference: reference, aspect: reference.size, visibleFrame: display) == .zero)
        }
    }

    @Test func invalidAspectUsesReferenceAndInvalidFramesAreRejected() {
        let display = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let reference = CGRect(x: 40, y: 50, width: 400, height: 300)
        for aspect in [CGSize.zero, CGSize(width: -1, height: 3), CGSize(width: CGFloat.infinity, height: 3)] {
            let frame = ReferencePreviewGeometry.frame(reference: reference, aspect: aspect, visibleFrame: display)
            #expect(frame.size == CGSize(width: 640, height: 480))
            #expect(!frame.intersects(reference))
        }
        for invalid in [CGRect.zero, CGRect.null, CGRect.infinite,
                        CGRect(x: 0, y: 0, width: -1600, height: 1000),
                        CGRect(x: 0, y: 0, width: 1600, height: -1000)] {
            #expect(ReferencePreviewGeometry.frame(reference: reference, aspect: reference.size, visibleFrame: invalid) == .zero)
            #expect(ReferencePreviewGeometry.frame(reference: invalid, aspect: reference.size, visibleFrame: display) == .zero)
        }
    }
}
