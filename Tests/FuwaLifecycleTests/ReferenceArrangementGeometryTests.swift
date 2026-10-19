import CoreGraphics
import FuwaCore
import Testing

struct ReferenceArrangementGeometryTests {
    @Test func emptyInputAndInvalidDisplaysKeepAnUnambiguousResult() {
        #expect(ReferenceArrangementGeometry.frames([], in: .zero).isEmpty)
        let inputs = [CGRect(x: 0, y: 0, width: 100, height: 50), CGRect.zero]
        for screen in [CGRect.zero, CGRect.null, CGRect.infinite,
                       CGRect(x: 0, y: 0, width: -800, height: 600),
                       CGRect(x: CGFloat.nan, y: 0, width: 800, height: 600)] {
            #expect(ReferenceArrangementGeometry.frames(inputs, in: screen) == [.zero, .zero])
        }
    }

    @Test func eachCornerKeepsSizesAndStacksInStableOrder() {
        let screen = CGRect(x: -1600, y: -900, width: 1600, height: 900)
        let inputs = [CGRect(x: 200, y: 200, width: 320, height: 180),
                      CGRect(x: 600, y: 500, width: 240, height: 120)]
        for corner in ReferenceArrangementCorner.allCases {
            let frames = ReferenceArrangementGeometry.frames(inputs, in: screen, corner: corner)
            #expect(frames.map(\.size) == inputs.map(\.size))
            #expect(frames.allSatisfy { screen.contains($0) })
            switch corner {
            case .topLeft:
                #expect(frames[0].minX == screen.minX + 16)
                #expect(frames[1].minX == frames[0].minX)
                #expect(frames[0].maxY == screen.maxY - 16)
                #expect(frames[1].maxY == frames[0].minY - 12)
            case .topRight:
                #expect(frames[0].maxX == screen.maxX - 16)
                #expect(frames[1].maxX == frames[0].maxX)
                #expect(frames[0].maxY == screen.maxY - 16)
                #expect(frames[1].maxY == frames[0].minY - 12)
            case .bottomLeft:
                #expect(frames[0].minX == screen.minX + 16)
                #expect(frames[1].minX == frames[0].minX)
                #expect(frames[0].minY == screen.minY + 16)
                #expect(frames[1].minY == frames[0].maxY + 12)
            case .bottomRight:
                #expect(frames[0].maxX == screen.maxX - 16)
                #expect(frames[1].maxX == frames[0].maxX)
                #expect(frames[0].minY == screen.minY + 16)
                #expect(frames[1].minY == frames[0].maxY + 12)
            }
        }
    }

    @Test func fullColumnContinuesInwardWithoutShrinking() {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 600)
        let inputs = Array(repeating: CGRect(x: 0, y: 0, width: 200, height: 200), count: 5)
        let frames = ReferenceArrangementGeometry.frames(inputs, in: screen)
        #expect(frames.map(\.size) == inputs.map(\.size))
        #expect(frames[0].maxX == frames[1].maxX)
        #expect(frames[2].maxX == frames[3].maxX)
        #expect(frames[2].maxX == frames[0].minX - 12)
        #expect(frames[4].maxX == frames[2].minX - 12)
        #expect(frames[2].maxY == frames[0].maxY)
        expectContainedWithoutOverlap(frames, in: screen)
    }

    @Test func eightMixedReferencesShrinkProportionallyOnSmallDisplays() {
        let inputs = (0..<8).map { index in
            CGRect(x: index * 40, y: index * 20, width: index.isMultiple(of: 2) ? 260 : 160,
                   height: index.isMultiple(of: 2) ? 160 : 260)
        }
        for screen in [CGRect(x: -800, y: 200, width: 640, height: 480),
                       CGRect(x: 1800, y: -400, width: 600, height: 400)] {
            for corner in ReferenceArrangementCorner.allCases {
                let frames = ReferenceArrangementGeometry.frames(inputs, in: screen, corner: corner)
                #expect(frames.count == inputs.count)
                let scale = frames[0].width / inputs[0].width
                #expect(scale > 0)
                #expect(scale < 1)
                for (original, result) in zip(inputs, frames) {
                    #expect(abs(result.width / original.width - scale) < 0.000001)
                    #expect(abs(result.height / original.height - scale) < 0.000001)
                }
                expectContainedWithoutOverlap(frames, in: screen)
                #expect(frames == ReferenceArrangementGeometry.frames(inputs, in: screen, corner: corner))
            }
        }
    }

    @Test func hugeAndInvalidReferencesRemainFiniteAndVisible() {
        let screen = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let inputs = [CGRect(x: 0, y: 0, width: 1_000_000, height: 500_000),
                      CGRect.zero, CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100),
                      CGRect(x: 0, y: 0, width: -100, height: 100)]
        let frames = ReferenceArrangementGeometry.frames(inputs, in: screen)
        #expect(frames.count == inputs.count)
        #expect(abs(frames[0].width / frames[0].height - 2) < 0.000001)
        for frame in frames.dropFirst() {
            #expect(abs(frame.width / frame.height - 16 / 9.0) < 0.000001)
        }
        expectContainedWithoutOverlap(frames, in: screen)
    }

    @Test func tinyDisplayStillKeepsAllEightReferencesInside() {
        let screen = CGRect(x: -25, y: -10, width: 50, height: 20)
        let inputs = Array(repeating: CGRect(x: 0, y: 0, width: 320, height: 180), count: 8)
        for corner in ReferenceArrangementCorner.allCases {
            expectContainedWithoutOverlap(ReferenceArrangementGeometry.frames(inputs, in: screen, corner: corner),
                                          in: screen)
        }
    }

    private func expectContainedWithoutOverlap(_ frames: [CGRect], in screen: CGRect) {
        for (index, frame) in frames.enumerated() {
            #expect(frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0)
            #expect(screen.contains(frame))
            for other in frames.dropFirst(index + 1) {
                #expect(!frame.intersects(other))
            }
        }
    }
}
